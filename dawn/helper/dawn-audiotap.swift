// dawn-audiotap: dawn's built-in macOS audio helper.
//
// Captures the sound your Mac is playing and writes it to stdout as raw 16-bit little-endian
// mono PCM, which is what dawn's audio visualiser reads. It uses Core Audio "process taps"
// (macOS 14.2 and newer), so no virtual audio device and no output rerouting is needed.
// Nothing is recorded to disk and nothing leaves your computer.
//
//   dawn-audiotap [--sample-rate N]   stream audio to stdout (default 22050 Hz)
//   dawn-audiotap --check             start the tap for a moment, then exit (triggers the permission prompt)
//   dawn-audiotap --version
//
// The way the tap and the private aggregate device are set up follows AudioTee
// (https://github.com/makeusabrew/audiotee), used under the MIT License:
//
//   The MIT License
//   Copyright (C) 2025 Nick Payne.
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software
//   and associated documentation files (the "Software"), to deal in the Software without
//   restriction, including without limitation the rights to use, copy, modify, merge, publish,
//   distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
//   Software is furnished to do so, subject to the following conditions: The above copyright
//   notice and this permission notice shall be included in all copies or substantial portions of
//   the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
//   PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
//   LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//   OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//   DEALINGS IN THE SOFTWARE.

import AudioToolbox
import CoreAudio
import Foundation

let helperVersion = "1"

/// Set by the signal handlers and by a failed write (dawn went away); the main loop checks it.
var stopRequested: Int32 = 0

func report(_ message: String) {
  FileHandle.standardError.write(Data(("dawn-audiotap: " + message + "\n").utf8))
}

func address(
  _ selector: AudioObjectPropertySelector,
  scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
  AudioObjectPropertyAddress(
    mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

/// Writes every byte to stdout. Returns false if the other end has closed the pipe.
func writeAll(_ pointer: UnsafeRawPointer, _ count: Int) -> Bool {
  var offset = 0
  while offset < count {
    let written = write(1, pointer.advanced(by: offset), count - offset)
    if written < 0 {
      if errno == EINTR { continue }
      return false
    }
    offset += written
  }
  return true
}

enum TapError: Error {
  case step(String, OSStatus)
  case message(String)
}

@available(macOS 14.2, *)
final class SystemAudioTap {
  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var deviceID = AudioObjectID(kAudioObjectUnknown)
  private var ioProc: AudioDeviceIOProcID?

  private let targetRate: Double
  private let writeOutput: Bool

  // What the tap delivers
  private var channels = 1
  private var isFloat = true
  private var bytesPerSample = 4
  private var interleaved = true

  // Down-mix to mono and average down to the target sample rate
  private var step = 1.0
  private var position = 0.0
  private var accumulator = 0.0
  private var accumulated = 0.0
  private var output = [Int16]()

  /// How many times Core Audio has handed us a buffer (used by --check).
  private(set) var callbacks = 0

  init(targetRate: Double, writeOutput: Bool) {
    self.targetRate = targetRate
    self.writeOutput = writeOutput
    output.reserveCapacity(4096)
  }

  func start() throws {
    // 1. A tap on everything the system plays. An empty process list that is "exclusive"
    //    means "every process except none", i.e. the whole system.
    let description = CATapDescription()
    description.name = "dawn-audiotap"
    description.processes = []
    description.isPrivate = true
    description.muteBehavior = .unmuted
    description.isMixdown = true
    description.isMono = true
    description.isExclusive = true
    description.deviceUID = nil
    description.stream = 0

    var status = AudioHardwareCreateProcessTap(description, &tapID)
    guard status == kAudioHardwareNoError else {
      throw TapError.step("create the audio tap", status)
    }

    // 2. A private aggregate device that has the tap as its input.
    let aggregate: [String: Any] = [
      kAudioAggregateDeviceNameKey: "dawn-audiotap-aggregate",
      kAudioAggregateDeviceUIDKey: UUID().uuidString,
      kAudioAggregateDeviceSubDeviceListKey: [] as CFArray,
      kAudioAggregateDeviceMasterSubDeviceKey: 0,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
    ]
    status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID)
    guard status == kAudioHardwareNoError else {
      throw TapError.step("create the audio device", status)
    }

    var uidAddress = address(kAudioTapPropertyUID)
    var uidSize = UInt32(MemoryLayout<CFString>.stride)
    var tapUID: CFString = "" as CFString
    status = withUnsafeMutablePointer(to: &tapUID) { pointer in
      AudioObjectGetPropertyData(tapID, &uidAddress, 0, nil, &uidSize, pointer)
    }
    guard status == kAudioHardwareNoError else {
      throw TapError.step("read the audio tap's id", status)
    }

    var listAddress = address(kAudioAggregateDevicePropertyTapList)
    let tapList = [tapUID] as CFArray
    let listSize = UInt32(MemoryLayout<CFArray>.stride)
    status = withUnsafePointer(to: tapList) { pointer in
      AudioObjectSetPropertyData(deviceID, &listAddress, 0, nil, listSize, pointer)
    }
    guard status == kAudioHardwareNoError else {
      throw TapError.step("attach the tap to the audio device", status)
    }

    // 3. Find out what format the tap delivers (it needs a moment to become ready).
    var format = AudioStreamBasicDescription()
    var gotFormat = false
    for _ in 0..<40 {
      var formatAddress = address(
        kAudioDevicePropertyStreamFormat, scope: kAudioDevicePropertyScopeInput)
      var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
      let result = AudioObjectGetPropertyData(
        deviceID, &formatAddress, 0, nil, &formatSize, &format)
      if result == noErr && format.mSampleRate > 0 {
        gotFormat = true
        break
      }
      usleep(50_000)
    }
    guard gotFormat else { throw TapError.message("couldn't read the audio format") }

    channels = max(1, Int(format.mChannelsPerFrame))
    isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
    interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
    bytesPerSample = Int(format.mBitsPerChannel) / 8
    guard (isFloat && bytesPerSample == 4) || (!isFloat && bytesPerSample == 2) else {
      throw TapError.message(
        "unsupported audio format (\(format.mBitsPerChannel)-bit, float: \(isFloat))")
    }
    step = max(1.0, format.mSampleRate / targetRate)

    // 4. Start reading.
    status = AudioDeviceCreateIOProcID(
      deviceID,
      {
        (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, inClientData)
          -> OSStatus in
        let tap = Unmanaged<SystemAudioTap>.fromOpaque(inClientData!).takeUnretainedValue()
        tap.handle(inInputData)
        return noErr
      },
      Unmanaged.passUnretained(self).toOpaque(),
      &ioProc
    )
    guard status == noErr else { throw TapError.step("start reading audio", status) }

    status = AudioDeviceStart(deviceID, ioProc)
    guard status == noErr else { throw TapError.step("start the audio device", status) }
  }

  func stop() {
    if let proc = ioProc {
      AudioDeviceStop(deviceID, proc)
      AudioDeviceDestroyIOProcID(deviceID, proc)
      ioProc = nil
    }
    if deviceID != kAudioObjectUnknown {
      AudioHardwareDestroyAggregateDevice(deviceID)
      deviceID = AudioObjectID(kAudioObjectUnknown)
    }
    if tapID != kAudioObjectUnknown {
      AudioHardwareDestroyProcessTap(tapID)
      tapID = AudioObjectID(kAudioObjectUnknown)
    }
  }

  @inline(__always)
  private func sample(_ pointer: UnsafeMutableRawPointer, _ index: Int) -> Double {
    if isFloat {
      return Double(pointer.assumingMemoryBound(to: Float.self)[index])
    }
    return Double(pointer.assumingMemoryBound(to: Int16.self)[index]) / 32768.0
  }

  /// Called by Core Audio about every 10 ms with the latest audio.
  fileprivate func handle(_ list: UnsafePointer<AudioBufferList>) {
    callbacks += 1
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
    guard buffers.count > 0, let first = buffers[0].mData, buffers[0].mDataByteSize > 0 else {
      return
    }

    let byteCount = Int(buffers[0].mDataByteSize)
    let frames = interleaved
      ? byteCount / (bytesPerSample * channels)
      : byteCount / bytesPerSample

    for frame in 0..<frames {
      var sum = 0.0
      if interleaved {
        for channel in 0..<channels { sum += sample(first, frame * channels + channel) }
        sum /= Double(channels)
      } else {
        let usable = min(buffers.count, channels)
        for channel in 0..<usable {
          if let data = buffers[channel].mData { sum += sample(data, frame) }
        }
        sum /= Double(max(1, usable))
      }

      accumulator += sum
      accumulated += 1
      position += 1
      if position >= step {
        var value = accumulator / accumulated
        if value.isNaN { value = 0 }
        value = max(-1.0, min(1.0, value))
        output.append(Int16(value * 32767.0))
        accumulator = 0
        accumulated = 0
        position -= step
      }
    }

    guard writeOutput, !output.isEmpty else {
      output.removeAll(keepingCapacity: true)
      return
    }
    let written = output.withUnsafeBytes { raw in writeAll(raw.baseAddress!, raw.count) }
    output.removeAll(keepingCapacity: true)
    if !written { stopRequested = 1 }  // dawn closed the pipe, so there is nobody to play for
  }
}

@available(macOS 14.2, *)
func run(rate: Double, checkOnly: Bool) -> Int32 {
  signal(SIGPIPE, SIG_IGN)
  signal(SIGINT) { _ in stopRequested = 1 }
  signal(SIGTERM) { _ in stopRequested = 1 }

  let tap = SystemAudioTap(targetRate: rate, writeOutput: !checkOnly)
  do {
    try tap.start()
  } catch TapError.step(let what, let status) {
    report(
      "couldn't \(what) (error \(status)). Check that your terminal is allowed under "
        + "System Settings > Privacy & Security > Screen & System Audio Recording.")
    tap.stop()
    return 1
  } catch TapError.message(let text) {
    report(text)
    tap.stop()
    return 1
  } catch {
    report("\(error)")
    tap.stop()
    return 1
  }

  if checkOnly {
    for _ in 0..<30 where tap.callbacks == 0 { usleep(50_000) }
    let working = tap.callbacks > 0
    tap.stop()
    if !working {
      report("the audio tap started but no audio arrived")
      return 1
    }
    print("ok")
    return 0
  }

  while stopRequested == 0 { usleep(50_000) }
  tap.stop()
  return 0
}

// MARK: - Command line

var targetRate = 22050.0
var checkOnly = false
let arguments = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < arguments.count {
  switch arguments[index] {
  case "--version":
    print("dawn-audiotap \(helperVersion)")
    exit(0)
  case "--check":
    checkOnly = true
  case "--sample-rate":
    index += 1
    guard index < arguments.count, let rate = Double(arguments[index]), rate >= 8000, rate <= 48000
    else {
      report("--sample-rate needs a number between 8000 and 48000")
      exit(2)
    }
    targetRate = rate
  case "--help", "-h":
    print("usage: dawn-audiotap [--sample-rate N] [--check] [--version]")
    exit(0)
  default:
    report("unknown option \(arguments[index])")
    exit(2)
  }
  index += 1
}

if #available(macOS 14.2, *) {
  exit(run(rate: targetRate, checkOnly: checkOnly))
} else {
  report("needs macOS 14.2 or newer")
  exit(3)
}
