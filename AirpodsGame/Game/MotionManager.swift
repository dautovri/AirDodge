import CoreMotion
import Combine

class MotionManager: ObservableObject {
    private let manager = CMHeadphoneMotionManager()
    private let smoothing: Double = 0.85

    @Published var pitch: Double = 0  // nod up/down, degrees
    @Published var roll: Double = 0   // tilt left/right, degrees
    @Published var yaw: Double = 0    // turn left/right, degrees
    @Published var isConnected = false

    private var smoothedPitch: Double = 0
    private var smoothedRoll: Double = 0

    static let shared = MotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            self.isConnected = true
            let rawPitch = motion.attitude.pitch * 180 / .pi
            let rawRoll  = motion.attitude.roll  * 180 / .pi
            self.smoothedPitch = self.smoothing * self.smoothedPitch + (1 - self.smoothing) * rawPitch
            self.smoothedRoll  = self.smoothing * self.smoothedRoll  + (1 - self.smoothing) * rawRoll
            self.pitch = self.smoothedPitch
            self.roll  = self.smoothedRoll
            self.yaw   = motion.attitude.yaw * 180 / .pi
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        isConnected = false
    }
}
