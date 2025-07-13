import Foundation
import CoreAudio

class AudioManager {
    static func setOutputSampleRate(to sampleRate: Double) -> Bool {
        // Don't attempt to change if sampleRate is 0 (indicates detection failure)
        guard sampleRate > 0 else {
            LogWriter.logNormal("Sample rate detection failed - keeping current rate")
            return false
        }
        
        LogWriter.logEssential("🚨 CRITICAL: Attempting to set sample rate to \(sampleRate) Hz")

        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout.size(ofValue: deviceID))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address,
                                                0,
                                                nil,
                                                &size,
                                                &deviceID)

        guard status == noErr else {
            LogWriter.logEssential("Failed to get output device (status: \(status))")
            return false
        }

        LogWriter.logDebug("Default output device ID: \(deviceID)")

        var rate = sampleRate
        let rateSize = UInt32(MemoryLayout.size(ofValue: rate))
        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        let setStatus = AudioObjectSetPropertyData(deviceID,
                                                  &rateAddress,
                                                  0,
                                                  nil,
                                                  rateSize,
                                                  &rate)

        if setStatus == noErr {
            LogWriter.logEssential("🚨 CRITICAL: ✅ Sample rate changed to \(rate) Hz")
            return true
        } else {
            LogWriter.logEssential("🚨 CRITICAL: ❌ Failed to change sample rate (code: \(setStatus))")
            return false
        }
    }

    static func getOutputDeviceName() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout.size(ofValue: deviceID))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address,
                                         0,
                                         nil,
                                         &size,
                                         &deviceID) == noErr else {
            return nil
        }

        var name: CFString?
        var nameSize = UInt32(MemoryLayout<CFString?>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, ptr)
        }

        return (status == noErr && name != nil) ? (name! as String) : nil
    }

    static func getBitDepth() -> UInt32? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address,
                                         0,
                                         nil,
                                         &size,
                                         &deviceID) == noErr else {
            return nil
        }

        var streamCountSize: UInt32 = 0
        var streamCountAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)

        if AudioObjectGetPropertyDataSize(deviceID, &streamCountAddr, 0, nil, &streamCountSize) != noErr {
            return nil
        }

        let streamCount = streamCountSize / UInt32(MemoryLayout<AudioStreamID>.size)
        var streams = [AudioStreamID](repeating: 0, count: Int(streamCount))
        AudioObjectGetPropertyData(deviceID, &streamCountAddr, 0, nil, &streamCountSize, &streams)

        for stream in streams {
            var desc = AudioStreamBasicDescription()
            var descSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var formatAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyVirtualFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)

            if AudioObjectGetPropertyData(stream, &formatAddress, 0, nil, &descSize, &desc) == noErr {
                return desc.mBitsPerChannel
            }
        }

        return nil
    }

    static func getAvailableSampleRates() -> [Double] {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout.size(ofValue: deviceID))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address,
                                         0,
                                         nil,
                                         &size,
                                         &deviceID) == noErr else {
            return []
        }

        var ratesSize = UInt32(0)
        var ratesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        guard AudioObjectGetPropertyDataSize(deviceID, &ratesAddress, 0, nil, &ratesSize) == noErr else {
            return []
        }

        let count = Int(ratesSize) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(mMinimum: 0, mMaximum: 0), count: count)

        guard AudioObjectGetPropertyData(deviceID, &ratesAddress, 0, nil, &ratesSize, &ranges) == noErr else {
            return []
        }

        var sampleRates = [Double]()
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                sampleRates.append(range.mMinimum)
            } else {
                // For ranges, add min and max as possible values
                sampleRates.append(range.mMinimum)
                sampleRates.append(range.mMaximum)
            }
        }

        return Array(Set(sampleRates)).sorted()
    }
}
