// PoC: SCStream system audio + microphone (SCStreamOutputType.microphone),
// no AVAudioEngine anywhere. Tests whether SCK mic capture survives a
// Bluetooth HFP/A2DP profile switch without blocking (production's
// AVAudioEngine installTap/start blocked ~59 min during a BT switch).
//
// Build:  swiftc -O main.swift -o recorder-poc
//         codesign -s - --force --entitlements entitlements.plist recorder-poc
//
// Protocol (stdin/stdout, one command per line), same as production:
//   start /absolute/path/to/output.m4a  →  STARTED | ERROR: <reason>
//   stop                                →  STOPPED_OK | STOPPED_ERROR: <reason>
//
// stderr: timestamped MIC_GAP <seconds> when a mic buffer gap > 500ms,
// and a per-10s "STAT sys_buffers=N mic_buffers=M" summary.

import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

private let kSampleRate: Double = 16_000
private let kBitrate:    Int    = 32_000
private let kChannels:   Int    = 1
private let kFragmentSeconds: Double = 10

private func aacOutputSettings() -> [String: Any] {
    [AVFormatIDKey:          kAudioFormatMPEG4AAC,
     AVSampleRateKey:        kSampleRate,
     AVNumberOfChannelsKey:  kChannels,
     AVEncoderBitRateKey:    kBitrate]
}

private let targetFmt = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate:   kSampleRate,
    channels:     AVAudioChannelCount(kChannels),
    interleaved:  false)!

// ─── stderr logging with timestamps ────────────────────────────
private let logTimeFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

private func log(_ s: String) {
    fputs("[\(logTimeFmt.string(from: Date()))] \(s)\n", stderr)
}

// ─── Unbuffered stdout ──────────────────────────────────────────
private func emit(_ s: String) {
    let bytes = Array((s + "\n").utf8)
    bytes.withUnsafeBytes { ptr in
        _ = Darwin.write(STDOUT_FILENO, ptr.baseAddress!, ptr.count)
    }
}

// ─── CMSampleBuffer → AVAudioPCMBuffer (for converting mic format) ────
private func pcmBuffer(from sb: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let fmtDesc = CMSampleBufferGetFormatDescription(sb),
          let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)
    else { return nil }
    guard let avFmt = AVAudioFormat(streamDescription: asbdPtr) else { return nil }

    let numSamples = CMSampleBufferGetNumSamples(sb)
    guard numSamples > 0,
          let pcm = AVAudioPCMBuffer(pcmFormat: avFmt, frameCapacity: AVAudioFrameCount(numSamples))
    else { return nil }
    pcm.frameLength = AVAudioFrameCount(numSamples)

    var abl = AudioBufferList()
    var blockBuffer: CMBlockBuffer?
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sb,
        bufferListSizeNeededOut: nil,
        bufferListOut: &abl,
        bufferListSize: MemoryLayout<AudioBufferList>.size,
        blockBufferAllocator: kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault,
        flags: 0,
        blockBufferOut: &blockBuffer)
    guard status == noErr else { return nil }

    guard let src = abl.mBuffers.mData, let dst = pcm.audioBufferList.pointee.mBuffers.mData else {
        return nil
    }
    let copySize = min(Int(abl.mBuffers.mDataByteSize),
                        Int(pcm.audioBufferList.pointee.mBuffers.mDataByteSize))
    memcpy(dst, src, copySize)
    return pcm
}

// ─── AVAudioPCMBuffer / CMSampleBuffer → CMSampleBuffer with PTS ──────
private func makeSampleBuffer(from pcm: AVAudioPCMBuffer, pts: CMTime) -> CMSampleBuffer? {
    var asbd = pcm.format.streamDescription.pointee
    var fmtDesc: CMAudioFormatDescription?
    guard CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault, asbd: &asbd,
        layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
        extensions: nil, formatDescriptionOut: &fmtDesc) == noErr,
        let fmt = fmtDesc else { return nil }

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: CMTimeScale(asbd.mSampleRate)),
        presentationTimeStamp: pts, decodeTimeStamp: .invalid)

    var sb: CMSampleBuffer?
    guard CMSampleBufferCreate(
        allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
        makeDataReadyCallback: nil, refcon: nil, formatDescription: fmt,
        sampleCount: CMItemCount(pcm.frameLength), sampleTimingEntryCount: 1,
        sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
        sampleBufferOut: &sb) == noErr, let result = sb else { return nil }

    guard CMSampleBufferSetDataBufferFromAudioBufferList(
        result, blockBufferAllocator: kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
        bufferList: pcm.audioBufferList) == noErr else { return nil }
    return result
}

private func restamp(_ original: CMSampleBuffer, pts: CMTime) -> CMSampleBuffer? {
    var timing = CMSampleTimingInfo(
        duration: CMSampleBufferGetDuration(original),
        presentationTimeStamp: pts, decodeTimeStamp: .invalid)
    var copy: CMSampleBuffer?
    return CMSampleBufferCreateCopyWithNewTiming(
        allocator: kCFAllocatorDefault, sampleBuffer: original,
        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
        sampleBufferOut: &copy) == noErr ? copy : nil
}

// ─── SCStream output/delegate ───────────────────────────────────
private final class SCOutputDelegate: NSObject, SCStreamOutput, SCStreamDelegate {
    unowned let engine: RecorderEngine
    init(engine: RecorderEngine) { self.engine = engine }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        engine.appendByType(buffer, type: type)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log("SCStream didStopWithError: \(error.localizedDescription)")
    }
}

enum RecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case micCaptureUnavailable

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "already_recording"
        case .notRecording: return "not_recording"
        case .micCaptureUnavailable: return "sck_mic_capture_requires_macos_15"
        }
    }
}

final class RecorderEngine {
    private(set) var isRecording = false

    private var writer:   AVAssetWriter?
    private var sysTrack: AVAssetWriterInput?
    private var micTrack: AVAssetWriterInput?

    private var stream: SCStream?
    private lazy var delegate = SCOutputDelegate(engine: self)

    private let writeQ = DispatchQueue(label: "poc.write", qos: .userInteractive)

    private var sysSamples: Int64 = 0
    private var micSamples: Int64 = 0

    // Stats (writeQ only)
    private var sysBufCount = 0
    private var micBufCount = 0
    private var lastMicBufferTime: Date?
    private var micConverter: AVAudioConverter?
    private var micFormatLoggedOnce = false
    private var statTimer: DispatchSourceTimer?

    private final class StopContext {
        let sema = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var emitted = false
        func markEmitted() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !emitted else { return false }
            emitted = true
            return true
        }
    }

    func start(path: String) throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }
        guard #available(macOS 15.0, *) else { throw RecorderError.micCaptureUnavailable }

        let dir = (path as NSString).deletingLastPathComponent
        if !dir.isEmpty {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let url = URL(fileURLWithPath: path)
        let w = try AVAssetWriter(outputURL: url, fileType: .m4a)
        w.movieFragmentInterval = CMTime(seconds: kFragmentSeconds, preferredTimescale: 600)

        let sys = AVAssetWriterInput(mediaType: .audio, outputSettings: aacOutputSettings())
        sys.expectsMediaDataInRealTime = true
        let mic = AVAssetWriterInput(mediaType: .audio, outputSettings: aacOutputSettings())
        mic.expectsMediaDataInRealTime = true
        w.add(sys)
        w.add(mic)

        guard w.startWriting() else {
            throw w.error ?? NSError(domain: "Recorder", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter failed to start"])
        }
        w.startSession(atSourceTime: .zero)

        writer = w; sysTrack = sys; micTrack = mic
        sysSamples = 0; micSamples = 0
        sysBufCount = 0; micBufCount = 0
        lastMicBufferTime = nil
        micConverter = nil
        micFormatLoggedOnce = false
        isRecording = true

        do {
            try startSCK()
        } catch {
            isRecording = false
            let fw = writer; writer = nil
            sysTrack = nil; micTrack = nil
            fw?.cancelWriting()
            throw error
        }

        startStatTimer()
    }

    private func startSCK() throws {
        let contentSema = DispatchSemaphore(value: 0)
        var content: SCShareableContent?
        var contentErr: Error?
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { c, e in
            content = c; contentErr = e; contentSema.signal()
        }
        if contentSema.wait(timeout: .now() + 10) == .timedOut {
            throw NSError(domain: "Recorder", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "getShareableContent timed out after 10s"])
        }
        if let e = contentErr { throw e }
        guard let display = content?.displays.first else {
            throw NSError(domain: "Recorder", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "no display found"])
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.capturesAudio               = true
        cfg.excludesCurrentProcessAudio = false
        cfg.sampleRate                  = Int(kSampleRate)
        cfg.channelCount                = kChannels
        cfg.captureMicrophone           = true
        cfg.microphoneCaptureDeviceID   = nil   // system default input
        cfg.width                       = 2
        cfg.height                      = 2
        cfg.minimumFrameInterval        = CMTime(value: 600, timescale: 1)
        cfg.queueDepth                  = 8

        let s = SCStream(filter: filter, configuration: cfg, delegate: delegate)
        try s.addStreamOutput(delegate, type: .audio, sampleHandlerQueue: writeQ)
        try s.addStreamOutput(delegate, type: .microphone, sampleHandlerQueue: writeQ)

        var captureErr: Error?
        let captureSema = DispatchSemaphore(value: 0)
        s.startCapture { e in captureErr = e; captureSema.signal() }
        if captureSema.wait(timeout: .now() + 10) == .timedOut {
            throw NSError(domain: "Recorder", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "startCapture timed out after 10s"])
        }
        if let e = captureErr { throw e }

        stream = s
        log("SCStream started (system audio + microphone, no AVAudioEngine)")
    }

    private func startStatTimer() {
        let t = DispatchSource.makeTimerSource(queue: writeQ)
        t.schedule(deadline: .now() + 10, repeating: 10)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            log("STAT sys_buffers=\(self.sysBufCount) mic_buffers=\(self.micBufCount)")
        }
        t.resume()
        statTimer = t
    }

    func appendByType(_ buffer: CMSampleBuffer, type: SCStreamOutputType) {
        switch type {
        case .audio:
            appendSystemAudio(buffer)
        case .microphone:
            appendMicAudio(buffer)
        default:
            break
        }
    }

    private func appendSystemAudio(_ buffer: CMSampleBuffer) {
        guard isRecording, let track = sysTrack, track.isReadyForMoreMediaData else { return }
        let n = CMSampleBufferGetNumSamples(buffer)
        guard n > 0 else { return }
        let pts = CMTime(value: sysSamples, timescale: CMTimeScale(kSampleRate))
        sysSamples += Int64(n)
        sysBufCount += 1
        if let stamped = restamp(buffer, pts: pts) {
            track.append(stamped)
        }
    }

    private func appendMicAudio(_ buffer: CMSampleBuffer) {
        let now = Date()
        if let last = lastMicBufferTime {
            let gap = now.timeIntervalSince(last)
            if gap > 0.5 {
                log("MIC_GAP \(String(format: "%.3f", gap))")
            }
        }
        lastMicBufferTime = now

        guard isRecording, let track = micTrack, track.isReadyForMoreMediaData else { return }
        let n = CMSampleBufferGetNumSamples(buffer)
        guard n > 0 else { return }

        guard let fmtDesc = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)?.pointee
        else { return }

        if !micFormatLoggedOnce {
            micFormatLoggedOnce = true
            log("mic buffer format: \(asbd.mSampleRate)Hz \(asbd.mChannelsPerFrame)ch "
                + "(target \(kSampleRate)Hz \(kChannels)ch)")
        }

        micBufCount += 1

        // Passthrough if the format already matches target; else convert.
        if asbd.mSampleRate == kSampleRate && Int(asbd.mChannelsPerFrame) == kChannels {
            let pts = CMTime(value: micSamples, timescale: CMTimeScale(kSampleRate))
            micSamples += Int64(n)
            if let stamped = restamp(buffer, pts: pts) {
                track.append(stamped)
            }
            return
        }

        guard let srcPCM = pcmBuffer(from: buffer) else { return }
        if micConverter == nil {
            micConverter = AVAudioConverter(from: srcPCM.format, to: targetFmt)
        }
        guard let converter = micConverter else { return }
        let ratio = kSampleRate / srcPCM.format.sampleRate
        let capacity = AVAudioFrameCount(Double(srcPCM.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFmt, frameCapacity: capacity) else { return }
        var consumed = false
        var convErr: NSError?
        converter.convert(to: converted, error: &convErr) { _, status in
            guard !consumed else { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return srcPCM
        }
        guard convErr == nil, converted.frameLength > 0 else { return }
        let pts = CMTime(value: micSamples, timescale: CMTimeScale(kSampleRate))
        micSamples += Int64(converted.frameLength)
        if let sb = makeSampleBuffer(from: converted, pts: pts) {
            track.append(sb)
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        statTimer?.cancel()
        statTimer = nil

        let context = StopContext()
        writeQ.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.finishWriter(context)
        }
        if context.sema.wait(timeout: .now() + 10) == .timedOut {
            writer = nil; sysTrack = nil; micTrack = nil
            emitStopResponse("STOPPED_ERROR: finishWriting_timeout", context: context)
        }
        teardownCapture()
    }

    private func teardownCapture() {
        guard let s = stream else { return }
        let sema = DispatchSemaphore(value: 0)
        s.stopCapture { _ in sema.signal() }
        _ = sema.wait(timeout: .now() + 10)
        stream = nil
    }

    private func finishWriter(_ context: StopContext) {
        sysTrack?.markAsFinished()
        micTrack?.markAsFinished()
        sysTrack = nil; micTrack = nil
        let w = writer
        writer = nil
        if let w {
            w.finishWriting { [weak self] in
                if let err = w.error {
                    self?.emitStopResponse("STOPPED_ERROR: \(err.localizedDescription)", context: context)
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
        emit(token)
        context.sema.signal()
    }
}

// ─── stdin protocol ──────────────────────────────────────────────
private let engine = RecorderEngine()

private func dispatchCmd(_ line: String) {
    let cmd = line.trimmingCharacters(in: .whitespaces)
    if cmd.hasPrefix("start ") {
        let path = String(cmd.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            fputs("ERROR: missing path\n", stderr)
            return
        }
        do {
            try engine.start(path: path)
            emit("STARTED")
        } catch {
            emit("ERROR: \(error.localizedDescription)")
        }
    } else if cmd == "stop" {
        engine.stop()
    } else if !cmd.isEmpty {
        fputs("ERROR: unknown command '\(cmd)'\n", stderr)
    }
}

private func runStdinProtocol() {
    DispatchQueue.global(qos: .userInteractive).async {
        while let line = readLine(strippingNewline: true) {
            dispatchCmd(line)
        }
        if engine.isRecording { engine.stop() }
        exit(0)
    }
}

setbuf(stdout, nil)
setbuf(stderr, nil)

// ─── --seconds N: non-interactive self-test mode ─────────────────
let argv = Array(CommandLine.arguments.dropFirst())
if let idx = argv.firstIndex(of: "--seconds"), idx + 1 < argv.count,
   let secs = Double(argv[idx + 1]), idx + 2 < argv.count {
    let path = argv[idx + 2]
    do {
        try engine.start(path: path)
        emit("STARTED")
        Thread.sleep(forTimeInterval: secs)
        engine.stop()
    } catch {
        emit("ERROR: \(error.localizedDescription)")
        exit(1)
    }
    exit(0)
} else {
    runStdinProtocol()
    RunLoop.main.run()
}
