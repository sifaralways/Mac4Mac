import AVFoundation
import Accelerate

protocol CaptureAudioTapDelegate: AnyObject {
    func didReceiveFFTData(_ magnitudes: [Float])
}

class CaptureAudioTap: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    weak var delegate: CaptureAudioTapDelegate?

    func start() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        guard let device = discoverySession.devices.first(where: { $0.localizedName.contains("BlackHole") }) else {
            print("❌ BlackHole device not found")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }

            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioQueue"))
            if session.canAddOutput(output) {
                session.addOutput(output)
            }

            session.startRunning()
            print("🎙️ CaptureAudioTap started using: \(device.localizedName)")
        } catch {
            print("❌ Failed to start capture session:", error)
        }
    }

    func stop() {
        session.stopRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr,
              let pointer = dataPointer else { return }

        guard length >= 2 else { return }
        let sampleCount = length / 2
        var maxSample: Int16 = 0

        for i in stride(from: 0, to: length - 1, by: 2) {
            let low = UInt8(bitPattern: pointer[i])
            let high = UInt8(bitPattern: pointer[i + 1])
            let sample = Int16(bitPattern: UInt16(high) << 8 | UInt16(low))
            maxSample = max(maxSample, abs(sample))
        }

        let normalized = Float(maxSample) / Float(Int16.max)
        guard normalized > 0.01 else { return }  // Skip silent buffers
        print("🔊 Captured Peak Volume: \(normalized)")

        // FFT Step
        var floatSamples = [Float](repeating: 0.0, count: sampleCount)
        for i in 0..<sampleCount {
            let low = UInt8(bitPattern: pointer[i * 2])
            let high = UInt8(bitPattern: pointer[i * 2 + 1])
            let sample = Int16(bitPattern: UInt16(high) << 8 | UInt16(low))
            floatSamples[i] = Float(sample) / Float(Int16.max)
        }

        let log2n = vDSP_Length(log2(Float(sampleCount)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }

        var real = floatSamples
        var imag = [Float](repeating: 0.0, count: sampleCount)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Magnitude
                var magnitudes = [Float](repeating: 0.0, count: sampleCount / 2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(sampleCount / 2))

                // Normalize (square root + scaling)
                var normalizedMagnitudes = [Float](repeating: 0.0, count: magnitudes.count)
                var scale: Float = 1.0 / Float(sampleCount)
                vDSP_vsmul(magnitudes, 1, &scale, &normalizedMagnitudes, 1, vDSP_Length(magnitudes.count))
                vvsqrtf(&normalizedMagnitudes, normalizedMagnitudes, [Int32(magnitudes.count)])

                // Send FFT data to delegate on main thread
                DispatchQueue.main.async {
                    self.delegate?.didReceiveFFTData(normalizedMagnitudes)
                }
            }
        }

        vDSP_destroy_fftsetup(fftSetup)
    }
}
