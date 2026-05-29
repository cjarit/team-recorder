// recorder/Sources/recorder/main.swift
// Teams Recorder v2 — standalone audio capture binary
//
// Build:     cd recorder && swift build -c release
//            cp .build/release/recorder recorder   (commit the result)
//            codesign -s - --force --entitlements entitlements.plist recorder
//
// Protocol (stdin/stdout, one command per line):
//   start /absolute/path/to/output.m4a  →  STARTED
//   stop                                →  STOPPED_OK | STOPPED_ERROR: <reason>
//   (stdin closed)                      →  exits cleanly
//
// CLI modes (exit immediately):
//   --check              prints OK + arch + macOS version
//   --list-devices       prints tab-separated: UID<TAB>name [type]
//   --device <UID>       override mic input device only (system audio uses default)
//   --request-permission triggers Screen Recording permission dialog

import AppKit
import AVFoundation
import CoreAudio
import Foundation
import ScreenCaptureKit

// ─── Audio output parameters ──────────────────────────────────
// ปรับสำหรับ ASR (Whisper/NotebookLM): 16 kHz mono 32 kbps ≈ 3.5 MB/hr
// kSampleRate ใช้ 3 จุด: aacOutputSettings, targetMicFmt, cfg.sampleRate
private let kSampleRate: Double = 16_000
private let kBitrate:    Int    = 32_000
private let kChannels:   Int    = 1

private func aacOutputSettings() -> [String: Any] {
    [AVFormatIDKey:          kAudioFormatMPEG4AAC,
     AVSampleRateKey:        kSampleRate,
     AVNumberOfChannelsKey:  kChannels,
     AVEncoderBitRateKey:    kBitrate]
}

// ─── Error types ──────────────────────────────────────────────
// ใช้ LocalizedError เพื่อให้ dispatch() catch เขียน token ที่ Python v2 อ่านได้
enum RecorderError: LocalizedError {
    case alreadyRecording
    case diskSpaceLow(mbFree: Int64)
    case screenRecordingPermissionDenied

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "already_recording"
        case .diskSpaceLow(let mb):
            // machine-readable prefix + human detail for logs
            return "disk_space_low — \(mb)MB free, need 200MB"
        case .screenRecordingPermissionDenied:
            return "screen_recording_permission_denied"
        }
    }
}

// ─── Disk space guard ─────────────────────────────────────────
// ขีดต่ำสุด 200MB — ต่ำกว่านี้ไฟล์มีความเสี่ยงเสียหาย
private let kMinFreeBytes: Int64 = 200 * 1024 * 1024

/// Returns free-space in MB if below threshold, nil if sufficient.
private func freeMBIfLow(at path: String) -> Int64? {
    let dir = (path as NSString).deletingLastPathComponent.isEmpty
              ? "." : (path as NSString).deletingLastPathComponent
    guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: dir),
          let free  = attrs[.systemFreeSize] as? Int64 else { return nil }
    return free < kMinFreeBytes ? free / 1024 / 1024 : nil
}

// ─── CoreAudio helpers (shared by --list-devices + RecorderEngine) ────
/// Read a CFString property from a CoreAudio object.
func coreAudioCFString(_ id: AudioObjectID,
                       _ sel: AudioObjectPropertySelector,
                       _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> String? {
    var p = AudioObjectPropertyAddress(mSelector: sel, mScope: scope,
                                       mElement: kAudioObjectPropertyElementMain)
    var ref: Unmanaged<CFString>? = nil
    var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &p, 0, nil, &s, &ref) == noErr else { return nil }
    return ref?.takeRetainedValue() as String?
}

/// Returns all CoreAudio device IDs on the system.
func allAudioDeviceIDs() -> [AudioDeviceID] {
    var sz: UInt32 = 0
    var prop = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope:    kAudioObjectPropertyScopeGlobal,
        mElement:  kAudioObjectPropertyElementMain)
    let sysObj = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(sysObj, &prop, 0, nil, &sz) == noErr else { return [] }
    let count = Int(sz) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(sysObj, &prop, 0, nil, &sz, &ids) == noErr else { return [] }
    return ids
}

/// Resolves a device UID string to a CoreAudio AudioDeviceID, or nil if not found.
func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
    for id in allAudioDeviceIDs() {
        if coreAudioCFString(id, kAudioDevicePropertyDeviceUID) == uid {
            return id
        }
    }
    return nil
}

// ─── PCM buffer → CMSampleBuffer ──────────────────────────────
// ใช้สำหรับแปลง AVAudioPCMBuffer จาก mic tap เป็น CMSampleBuffer
// เพื่อ append ให้ AVAssetWriterInput
private func makeSampleBuffer(from pcm: AVAudioPCMBuffer,
                               pts: CMTime) -> CMSampleBuffer? {
    var asbd = pcm.format.streamDescription.pointee

    var fmtDesc: CMAudioFormatDescription?
    guard CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &asbd,
        layoutSize: 0, layout: nil,
        magicCookieSize: 0, magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &fmtDesc
    ) == noErr, let fmt = fmtDesc else { return nil }

    var timing = CMSampleTimingInfo(
        duration:               CMTime(value: 1, timescale: CMTimeScale(asbd.mSampleRate)),
        presentationTimeStamp:  pts,
        decodeTimeStamp:        .invalid)

    var sb: CMSampleBuffer?
    guard CMSampleBufferCreate(
        allocator:              kCFAllocatorDefault,
        dataBuffer:             nil,
        dataReady:              false,
        makeDataReadyCallback:  nil,
        refcon:                 nil,
        formatDescription:      fmt,
        sampleCount:            CMItemCount(pcm.frameLength),
        sampleTimingEntryCount: 1,
        sampleTimingArray:      &timing,
        sampleSizeEntryCount:   0,
        sampleSizeArray:        nil,
        sampleBufferOut:        &sb
    ) == noErr, let result = sb else { return nil }

    guard CMSampleBufferSetDataBufferFromAudioBufferList(
        result,
        blockBufferAllocator:       kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault,
        flags:                      0,
        bufferList:                 pcm.audioBufferList
    ) == noErr else { return nil }

    return result
}

// ─── Re-timestamp a CMSampleBuffer ────────────────────────────
// SCK delivers CMSampleBuffers with absolute host-clock timestamps.
// We replace the PTS with a session-relative sample-count timestamp.
private func restamp(_ original: CMSampleBuffer,
                     pts: CMTime) -> CMSampleBuffer? {
    var timing = CMSampleTimingInfo(
        duration:               CMSampleBufferGetDuration(original),
        presentationTimeStamp:  pts,
        decodeTimeStamp:        .invalid)
    var copy: CMSampleBuffer?
    return CMSampleBufferCreateCopyWithNewTiming(
        allocator:                  kCFAllocatorDefault,
        sampleBuffer:               original,
        sampleTimingEntryCount:     1,
        sampleTimingArray:          &timing,
        sampleBufferOut:            &copy
    ) == noErr ? copy : nil
}

// ─── SCStream output/delegate ─────────────────────────────────
private class SCOutputDelegate: NSObject, SCStreamOutput, SCStreamDelegate {
    // unowned is safe: engine lives for the duration of the process
    unowned let engine: RecorderEngine

    init(engine: RecorderEngine) { self.engine = engine }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer buffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }
        engine.appendSystemAudio(buffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Dispatch to main so handleSCKStreamStop shares a queue with the wake observer
        DispatchQueue.main.async { [weak self] in
            self?.engine.handleSCKStreamStop(error)
        }
    }
}

// ─── Recorder engine ──────────────────────────────────────────
final class RecorderEngine {

    private(set) var isRecording = false

    // AVAssetWriter — two-track m4a:
    //   sysTrack  = system audio (ScreenCaptureKit)
    //   micTrack  = microphone (AVAudioEngine)
    // Both tracks play simultaneously on any standard player → effective mix.
    private var writer:   AVAssetWriter?
    private var sysTrack: AVAssetWriterInput?
    private var micTrack: AVAssetWriterInput?

    // SCK
    private var sckStream:   SCStream?
    private lazy var sckDelegate = SCOutputDelegate(engine: self)

    // AVAudioEngine (mic) — var so startMic() can replace it each session
    private var audioEngine    = AVAudioEngine()
    private var micConverter:  AVAudioConverter?
    private var micConfigObserver: NSObjectProtocol?
    private var micRestartPending = false

    // SCK stream recovery (sleep/wake, display change)
    // Both flags and the wake observer are only touched on the main queue
    private var sckRestartPending = false
    private var sckWakeObserver:   NSObjectProtocol?
    private let targetMicFmt = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate:   kSampleRate,
        channels:     AVAudioChannelCount(kChannels),
        interleaved:  false)!

    // Serial queue — all AVAssetWriterInput appends happen here
    // ป้องกัน data race ระหว่าง SCK callback กับ mic tap
    private let writeQ = DispatchQueue(label: "io.teams-recorder.write",
                                       qos: .userInteractive)

    // Sample counters → PTS (sample counting เลี่ยง host-clock drift)
    private var sysSamples: Int64 = 0
    private var micSamples: Int64 = 0

    private final class StopContext {
        let sema = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var emitted = false
        private var writer: AVAssetWriter?

        func setWriter(_ writer: AVAssetWriter?) {
            lock.lock()
            self.writer = writer
            lock.unlock()
        }

        func cancelWriter() {
            lock.lock()
            let w = writer
            writer = nil
            lock.unlock()
            w?.cancelWriting()
        }

        func markEmitted() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !emitted else { return false }
            emitted = true
            writer = nil
            return true
        }
    }

    // Tracks the current stop only so timeout cleanup can find the writer.
    private let finishLock = NSLock()
    private var finishContext: StopContext?

    // MARK: – Start

    func start(path: String) throws {
        // ─ guard: throw (not return) so dispatch() never emits false STARTED
        guard !isRecording else {
            throw RecorderError.alreadyRecording
        }
        if let mbFree = freeMBIfLow(at: path) {
            throw RecorderError.diskSpaceLow(mbFree: mbFree)
        }

        // Ensure output directory exists
        let dir = (path as NSString).deletingLastPathComponent
        if !dir.isEmpty {
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
        }

        let url = URL(fileURLWithPath: path)
        let w   = try AVAssetWriter(outputURL: url, fileType: .m4a)

        let sys = AVAssetWriterInput(mediaType: .audio,
                                      outputSettings: aacOutputSettings())
        sys.expectsMediaDataInRealTime = true

        let mic = AVAssetWriterInput(mediaType: .audio,
                                      outputSettings: aacOutputSettings())
        mic.expectsMediaDataInRealTime = true

        w.add(sys)
        w.add(mic)

        guard w.startWriting() else {
            throw w.error ?? NSError(
                domain: "RecorderError", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter failed to start"])
        }
        w.startSession(atSourceTime: .zero)

        writer    = w
        sysTrack  = sys
        micTrack  = mic
        sysSamples = 0
        micSamples = 0
        isRecording = true

        // Start mic (non-fatal if permission denied — falls back to system audio only)
        startMic()

        // Start SCK (fatal if permission denied or display unavailable)
        do {
            try startSCK()
        } catch {
            // ── Rollback: SCK failed → undo everything so the session is clean ──
            // ถ้า SCK ล้มเหลว ต้อง rollback state ทั้งหมดก่อน throw ต่อ
            isRecording = false
            stopMic()
            let failedWriter = writer; writer = nil
            sysTrack = nil; micTrack = nil
            failedWriter?.cancelWriting()
            throw error
        }
    }

    // MARK: – Stop

    /// Synchronous: blocks until the file is fully written to disk.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        stopMic()
        stopSCK()
        // Short grace so any in-flight buffers on writeQ can land
        let context = StopContext()
        finishLock.lock()
        finishContext = context
        finishLock.unlock()
        writeQ.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.finishWriter(context)
        }
        if context.sema.wait(timeout: .now() + 10) == .timedOut {
            context.cancelWriter()
            writer = nil
            sysTrack = nil
            micTrack = nil
            emitStopResponse("STOPPED_ERROR: finishWriting_timeout", context: context)
        }
    }

    // MARK: – Mic (AVAudioEngine)

    private func startMic() {
        // Fresh engine each session: reset() alone leaves stale format state that
        // causes installTap to throw "format mismatch" on the second recording.
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode

        // ถ้าผู้ใช้ระบุ device UID ไว้ ให้ set ก่อน read format (format ขึ้นกับ device)
        if let uid = selectedDeviceUID {
            if !setAudioEngineInputDevice(uid: uid) {
                fputs("[recorder] device '\(uid)' not found or not an input — using default mic\n",
                      stderr)
            }
        }

        let hwFmt     = inputNode.outputFormat(forBus: 0)
        micConverter  = AVAudioConverter(from: hwFmt, to: targetMicFmt)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFmt) {
            [weak self] buffer, _ in self?.handleMicBuffer(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
            micConfigObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: audioEngine,
                queue: .main
            ) { [weak self] _ in self?.handleMicConfigChange() }
        } catch {
            // Mic unavailable (permission denied, no input device) — continue with system audio
            fputs("[recorder] mic unavailable: \(error.localizedDescription) — system audio only\n",
                  stderr)
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    private func stopMic() {
        if let obs = micConfigObserver {
            NotificationCenter.default.removeObserver(obs)
            micConfigObserver = nil
        }
        micRestartPending = false
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        micConverter = nil
        // no reset() — startMic() replaces the engine entirely
    }

    private func handleMicConfigChange(retryCount: Int = 0, outageStart: Date = Date()) {
        guard isRecording, !micRestartPending else { return }
        micRestartPending = true
        if retryCount == 0 {
            fputs("[recorder] audio input device changed — restarting mic tap\n", stderr)
        }

        // Remove old observer (safe to call from inside the observer callback)
        if let obs = micConfigObserver {
            NotificationCenter.default.removeObserver(obs)
            micConfigObserver = nil
        }
        // Raw teardown — removeTap on an already-invalidated tap is a no-op
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        micConverter = nil

        // 0.5 s settle: macOS needs a moment to fully expose the new default device
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isRecording else { return }

            // Advance micSamples BEFORE starting the engine so the first resumed buffer
            // is written with the correct post-gap timestamp (not the pre-gap value).
            // Measured from the original disconnect so retries don't double-advance.
            let gapFrames = Int64(Date().timeIntervalSince(outageStart) * kSampleRate)
            self.writeQ.sync { self.micSamples += gapFrames }

            self.startMic()  // fresh engine + re-installs tap + re-registers observer

            if self.micConfigObserver != nil {
                self.micRestartPending = false
            } else if retryCount < 3 {
                // startMic failed — undo the gap advance so next retry re-measures correctly
                self.writeQ.sync { self.micSamples -= gapFrames }
                // startMic failed (device not ready) — retry with backoff
                let delay = Double(retryCount + 1)   // 1s, 2s, 3s
                fputs("[recorder] mic restart failed — retry \(retryCount+1)/3 in \(delay)s\n",
                      stderr)
                self.micRestartPending = false
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.handleMicConfigChange(retryCount: retryCount + 1,
                                               outageStart: outageStart)
                }
            } else {
                // All retries exhausted — undo gap advance; mic will be silent for remainder
                self.writeQ.sync { self.micSamples -= gapFrames }
                fputs("[recorder] mic restart failed after 3 retries — continuing without mic\n",
                      stderr)
                self.micRestartPending = false
            }
        }
    }

    /// Sets AVAudioEngine's input to the CoreAudio device with the given UID.
    /// Returns false if UID is not found or setting fails.
    private func setAudioEngineInputDevice(uid: String) -> Bool {
        guard let deviceID = audioDeviceID(forUID: uid) else { return false }
        guard let au = audioEngine.inputNode.audioUnit else { return false }
        var devID = deviceID
        return AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr
    }

    private func handleMicBuffer(_ inputBuf: AVAudioPCMBuffer) {
        guard let converter = micConverter else { return }

        let ratio = kSampleRate / inputBuf.format.sampleRate
        let capacity = AVAudioFrameCount(Double(inputBuf.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetMicFmt,
                                                frameCapacity: capacity) else { return }
        var inputConsumed = false
        var convErr: NSError?
        converter.convert(to: converted, error: &convErr) { _, status in
            guard !inputConsumed else { status.pointee = .noDataNow; return nil }
            inputConsumed = true
            status.pointee = .haveData
            return inputBuf
        }
        guard convErr == nil, converted.frameLength > 0 else { return }

        // Capture frameLength before async dispatch (Swift 6 sendability)
        let frameLength = converted.frameLength

        writeQ.async { [weak self, converted] in
            guard let self, self.isRecording,
                  let track = self.micTrack, track.isReadyForMoreMediaData else { return }
            let pts = CMTime(value: self.micSamples,
                             timescale: CMTimeScale(kSampleRate))
            self.micSamples += Int64(frameLength)
            if let sb = makeSampleBuffer(from: converted, pts: pts) {
                track.append(sb)
            }
        }
    }

    // MARK: – SCK (system audio)

    /// Pure factory: fetches shareable content, configures, and starts a fresh SCStream.
    /// Does NOT mutate any engine state — the caller owns the returned stream and must
    /// assign sckStream / register the wake observer on the main queue.
    /// Safe to call on any queue; all blocking semaphore work is contained here.
    private func buildSCKStream() throws -> SCStream {
        // ─ 1. Fetch shareable content ─────────────────────────────────────────
        let contentSema = DispatchSemaphore(value: 0)
        var capturedContent: SCShareableContent?
        var capturedError:   Error?

        // ขอ content list จาก SCK — trigger permission prompt ถ้ายังไม่ grant
        SCShareableContent.getExcludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ) { content, error in
            capturedContent = content
            capturedError   = error
            contentSema.signal()
        }
        // S2: ถ้า SCK callback ไม่ตอบภายใน 10s → TCC denial หรือ system hang
        if contentSema.wait(timeout: .now() + 10) == .timedOut {
            fputs("→ System Settings → Privacy & Security → Screen Recording → enable Terminal\n",
                  stderr)
            throw RecorderError.screenRecordingPermissionDenied
        }

        if let err = capturedError {
            let ns = err as NSError
            let denied = (ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
                          && ns.code == -3801)
                      || ns.localizedDescription.lowercased().contains("permission")
                      || ns.localizedDescription.lowercased().contains("tcc")
            if denied {
                fputs("→ System Settings → Privacy & Security → Screen Recording → enable Terminal\n",
                      stderr)
                throw RecorderError.screenRecordingPermissionDenied
            } else {
                throw err
            }
        }

        guard let content = capturedContent else {
            throw NSError(domain: "RecorderError", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "no shareable content returned"])
        }

        // ─ 2. Configure stream ─────────────────────────────────────────────────
        guard let display = content.displays.first else {
            throw NSError(domain: "RecorderError", code: 4,
                          userInfo: [NSLocalizedDescriptionKey:
                              "no display found — cannot capture system audio"])
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: [])

        let cfg = SCStreamConfiguration()
        cfg.capturesAudio               = true
        cfg.excludesCurrentProcessAudio = false
        cfg.sampleRate                  = Int(kSampleRate)
        cfg.channelCount                = kChannels
        // Video config — minimal overhead; we only use the audio output type
        cfg.width                       = 2
        cfg.height                      = 2
        cfg.minimumFrameInterval        = CMTime(value: 600, timescale: 1)  // ~1/600 fps
        cfg.queueDepth                  = 8

        let stream = SCStream(filter: filter,
                              configuration: cfg,
                              delegate: sckDelegate)

        // ส่ง audio buffers มาที่ writeQ โดยตรง (thread-safe กับ mic path)
        // ใช้ try (ไม่ใช่ try?) เพื่อ propagate error ขึ้นไปให้ caller rollback ได้
        try stream.addStreamOutput(sckDelegate, type: .audio,
                                   sampleHandlerQueue: writeQ)

        // ─ 3. Start capture ────────────────────────────────────────────────────
        var captureError: Error?
        let captureSema = DispatchSemaphore(value: 0)
        stream.startCapture { error in
            captureError = error
            captureSema.signal()
        }
        if captureSema.wait(timeout: .now() + 10) == .timedOut {
            throw NSError(domain: "RecorderError", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "startCapture timed out after 10s"])
        }
        if let err = captureError { throw err }

        return stream
    }

    /// Registers the NSWorkspace wake observer that guards against SCK dropping audio
    /// after sleep without firing didStopWithError. Safe to call from any queue
    /// (NSWorkspace observer registration is thread-safe); removes any existing observer
    /// first so it is safe to call at any time without leaking a token.
    private func registerSCKWakeObserver() {
        // Defensive removal: callers typically clear the observer before calling, but
        // remove defensively here so double-registration can never leak a token.
        if let existing = sckWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(existing)
            sckWakeObserver = nil
        }
        // Belt-and-suspenders: trigger a restart on wake even if didStopWithError
        // doesn't fire (some macOS versions reconnect the stream but audio is broken).
        // The sckRestartPending guard makes this a no-op if didStopWithError won the race.
        sckWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            guard let self, self.isRecording, !self.sckRestartPending else { return }
            fputs("[recorder] wake from sleep — triggering SCK restart\n", stderr)
            let err = NSError(domain: "com.teams-recorder", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: "sleep/wake"])
            self.handleSCKStreamStop(err)
        }
    }

    /// Builds and installs a fresh SCK stream. Throws on any failure so start() can
    /// perform a clean rollback. Called on a background queue; assigns sckStream and
    /// sckWakeObserver once the stream is live (same threading model as the original).
    private func startSCK() throws {
        let stream = try buildSCKStream()
        sckStream = stream
        registerSCKWakeObserver()
    }

    private func stopSCK() {
        if let obs = sckWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            sckWakeObserver = nil
        }
        sckRestartPending = false
        guard let stream = sckStream else { return }
        let sema = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in sema.signal() }
        _ = sema.wait(timeout: .now() + 10)  // timeout → proceed; file flush was already done
        sckStream = nil
    }

    // Called on main queue from SCOutputDelegate and the wake observer.
    // Restarts the SCK stream in-place without touching AVAssetWriter.
    // Mirrors handleMicConfigChange: advance the sample counter to cover the silent gap
    // so the resumed buffers land at the correct PTS.
    //
    // Threading model (enforced, not just aspirational):
    //   • All sckStream / sckWakeObserver / sckRestartPending reads+writes: main queue
    //   • Blocking work (stopCapture, buildSCKStream semaphores): background queue
    //   • Second isRecording gate on main before installing the new stream prevents
    //     a revived SCK stream after user stop.
    func handleSCKStreamStop(_ error: Error) {
        // ─ 1. Main queue: guard + capture state ───────────────────────────────
        guard isRecording, !sckRestartPending else { return }
        sckRestartPending = true
        let outageStart = Date()
        fputs("[recorder] SCStream stopped: \(error.localizedDescription) — restarting\n", stderr)

        // Remove old wake observer and capture the old stream before clearing sckStream.
        // oldStream may still be alive when called from the wake observer (didStopWithError
        // did not fire), so we need to stop it explicitly on the background queue.
        if let obs = sckWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            sckWakeObserver = nil
        }
        let oldStream = sckStream
        sckStream = nil

        // Short settle: give macOS time to expose the display after wake/reconnect.
        // Then dispatch ALL blocking work to a background queue.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isRecording else { return }

            let gapFrames = Int64(Date().timeIntervalSince(outageStart) * kSampleRate)

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }

                // ─ 2. Background: stop old stream + build replacement ──────────
                // Explicitly stop old stream if still alive (always the wake-observer path)
                if let old = oldStream {
                    let stopSema = DispatchSemaphore(value: 0)
                    old.stopCapture { _ in stopSema.signal() }
                    _ = stopSema.wait(timeout: .now() + 5)
                }

                // Advance sysSamples to cover the outage so resumed buffers have correct PTS.
                // writeQ.sync is safe on a background queue (no main → writeQ → main path).
                self.writeQ.sync { self.sysSamples += gapFrames }

                // Build the replacement stream without touching any engine state
                let result = Result { try self.buildSCKStream() }

                // ─ 3. Main queue: second gate + install or discard ────────────
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }

                    switch result {
                    case .success(let newStream):
                        // Second gate: verify recording is still active and a concurrent
                        // stop() hasn't already called stopSCK().
                        guard self.isRecording, self.sckRestartPending else {
                            // Recording ended during the restart window — discard the stream.
                            newStream.stopCapture { _ in }
                            self.sckRestartPending = false
                            return
                        }
                        // Install on main: these writes now stay on the main queue.
                        self.sckStream = newStream
                        self.registerSCKWakeObserver()
                        self.sckRestartPending = false
                        fputs("[recorder] SCStream restarted successfully\n", stderr)

                    case .failure(let error):
                        // Undo the sample advance so any future restart re-measures the gap.
                        // writeQ.async avoids a sync-from-main deadlock risk.
                        self.writeQ.async { self.sysSamples -= gapFrames }
                        self.sckRestartPending = false
                        fputs("[recorder] SCStream restart failed: \(error.localizedDescription)"
                              + " — system audio silent for remainder of recording\n", stderr)
                    }
                }
            }
        }
    }

    // Called from SCOutputDelegate on writeQ
    func appendSystemAudio(_ buffer: CMSampleBuffer) {
        guard isRecording,
              let track = sysTrack, track.isReadyForMoreMediaData else { return }
        let n   = CMSampleBufferGetNumSamples(buffer)
        let pts = CMTime(value: sysSamples, timescale: CMTimeScale(kSampleRate))
        sysSamples += Int64(n)
        if let stamped = restamp(buffer, pts: pts) {
            track.append(stamped)
        }
    }

    // MARK: – Finish

    private func finishWriter(_ context: StopContext) {
        sysTrack?.markAsFinished()
        micTrack?.markAsFinished()
        sysTrack = nil
        micTrack = nil
        let w = writer
        writer = nil
        context.setWriter(w)
        if let w {
            w.finishWriting { [weak self] in
                // Emit outcome token so Python can distinguish success from disk/AVFoundation errors.
                // Python renames as INCOMPLETE on STOPPED_ERROR instead of silently producing
                // a well-named but damaged file.
                if let err = w.error {
                    self?.emitStopResponse("STOPPED_ERROR: \(err.localizedDescription)",
                                           context: context)
                } else {
                    self?.emitStopResponse("STOPPED_OK", context: context)
                }
            }
        } else {
            emitStopResponse("STOPPED_OK", context: context)
        }
    }

    private func emitStopResponse(_ token: String, context: StopContext) {
        guard context.markEmitted() else { return }

        finishLock.lock()
        if finishContext === context {
            finishContext = nil
        }
        finishLock.unlock()

        emit(token)
        context.sema.signal()
    }
}

// ─── CLI: --check ─────────────────────────────────────────────
func runCheck() {
    let arch: String
    #if arch(arm64)
    arch = "arm64"
    #elseif arch(x86_64)
    arch = "x86_64"
    #else
    arch = "unknown"
    #endif
    let v = ProcessInfo.processInfo.operatingSystemVersion
    print("OK")
    print("arch: \(arch)")
    print("macos: \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
}

// ─── CLI: --list-devices ──────────────────────────────────────
func runListDevices() {
    func hasChannels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var p = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                           mScope: scope,
                                           mElement: kAudioObjectPropertyElementMain)
        var sz: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &p, 0, nil, &sz) == noErr, sz > 0 else {
            return false
        }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(sz), alignment: 4)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &p, 0, nil, &sz, buf) == noErr else { return false }
        let abl = buf.bindMemory(to: AudioBufferList.self, capacity: 1)
        return abl.pointee.mNumberBuffers > 0
    }

    let ids = allAudioDeviceIDs()
    guard !ids.isEmpty else {
        fputs("ERROR: cannot enumerate audio devices\n", stderr)
        return
    }

    for id in ids {
        let uid  = coreAudioCFString(id, kAudioDevicePropertyDeviceUID)         ?? "(no-uid)"
        let name = coreAudioCFString(id, kAudioDevicePropertyDeviceNameCFString) ?? "(no name)"
        var types: [String] = []
        if hasChannels(id, kAudioObjectPropertyScopeInput)  { types.append("input") }
        if hasChannels(id, kAudioObjectPropertyScopeOutput) { types.append("output") }
        print("\(uid)\t\(name) [\(types.joined(separator: "/"))]")
    }
}

// ─── CLI: --request-permission ────────────────────────────────
// NOTE: For a bare CLI binary, the permission dialog appears under the parent
// process name (e.g. "Terminal") rather than "recorder". This is expected macOS
// behaviour — the binary just needs *some* process in the Screen Recording list.
func runRequestPermission() {
    let sema = DispatchSemaphore(value: 0)
    var granted = false

    SCShareableContent.getExcludingDesktopWindows(
        false, onScreenWindowsOnly: false
    ) { _, error in
        if error == nil {
            granted = true
            print("OK: Screen Recording permission granted")
        } else {
            fputs("ERROR: Screen Recording permission not granted\n", stderr)
            fputs("→ System Settings → Privacy & Security → Screen Recording → enable Terminal\n",
                  stderr)
        }
        sema.signal()
    }

    if sema.wait(timeout: .now() + 10) == .timedOut {
        fputs("ERROR: Screen Recording permission check timed out after 10s\n", stderr)
        exit(1)
    }
    exit(granted ? 0 : 1)
}

// ─── Unbuffered stdout helper ─────────────────────────────────
// Swift print() + fflush() can still buffer through a pipe on newer macOS.
// Use raw POSIX write() directly to the file descriptor — always immediate.
private func emit(_ s: String) {
    let bytes = Array((s + "\n").utf8)
    bytes.withUnsafeBytes { ptr in
        _ = Darwin.write(STDOUT_FILENO, ptr.baseAddress!, ptr.count)
    }
}

// ─── stdin protocol ───────────────────────────────────────────
private let engine = RecorderEngine()

private func dispatch(_ line: String) {
    let cmd = line.trimmingCharacters(in: .whitespaces)
    if cmd.hasPrefix("start ") {
        let path = String(cmd.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            fputs("ERROR: missing path — usage: start /path/to/output.m4a\n", stderr)
            return
        }
        do {
            try engine.start(path: path)
            emit("STARTED")
        } catch {
            // error.localizedDescription เป็น machine-readable token สำหรับ Python v2
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
        }
    } else if cmd == "stop" {
        engine.stop()
        // STOPPED_OK / STOPPED_ERROR emitted by the per-stop StopContext path
    } else if !cmd.isEmpty {
        fputs("ERROR: unknown command '\(cmd)'\n", stderr)
    }
}

private func runStdinProtocol() {
    DispatchQueue.global(qos: .userInteractive).async {
        while let line = readLine(strippingNewline: true) {
            dispatch(line)
        }
        // stdin closed (Python process exited) — stop cleanly
        if engine.isRecording { engine.stop() }
        exit(0)
    }
}

// ─── Entry point ──────────────────────────────────────────────
// Set stdout AND stderr to unbuffered so Python readline() sees responses
// immediately. On macOS, both are block-buffered when connected to a pipe.
setbuf(stdout, nil)
setbuf(stderr, nil)

var argv = Array(CommandLine.arguments.dropFirst())

// ── Parse --device <UID> (applies to stdin protocol mode) ──────
// UID จาก recorder --list-devices — ใช้ override mic input device
// System audio (SCK) ยึด default display audio output ไม่ว่าจะ set device อะไร
var selectedDeviceUID: String? = nil
if let idx = argv.firstIndex(of: "--device"), idx + 1 < argv.count {
    selectedDeviceUID = argv[idx + 1]
    argv.remove(at: idx + 1)
    argv.remove(at: idx)
}

switch true {
case argv.contains("--check"):
    runCheck(); exit(0)
case argv.contains("--list-devices"):
    runListDevices(); exit(0)
case argv.contains("--request-permission"):
    runRequestPermission()      // calls exit() internally
    exit(1)                     // unreachable; satisfies compiler
default:
    runStdinProtocol()
    RunLoop.main.run()          // keep process alive while recording
}
