import SwiftUI
import AVFoundation

struct CameraCaptureView: UIViewControllerRepresentable {
    let captured: (Result<Data, Error>?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(captured: captured) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let captured: (Result<Data, Error>?) -> Void
        init(captured: @escaping (Result<Data, Error>?) -> Void) { self.captured = captured }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { captured(nil) }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) else {
                captured(.failure(TranslationError.invalidImage)); return
            }
            captured(.success(data))
        }
    }
}

enum CameraAccess {
    @MainActor static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}
