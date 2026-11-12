//
//  DCImageViewerController.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import UIKit

/// A picture from the book, full screen: pinch or double-tap to zoom, swipe down or Done to close.
final class DCImageViewerController: UIViewController, UIScrollViewDelegate {

    private let image: UIImage
    private let imageDescription: String
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    init(image: UIImage, description: String) {
        self.image = image
        self.imageDescription = description
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        // Over full screen, the presenter keeps control of the status bar unless this is set.
        modalPresentationCapturesStatusBarAppearance = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        imageView.accessibilityLabel = imageDescription.isEmpty ? "Image" : imageDescription
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(swipeToClose))
        swipeDown.direction = .down
        scrollView.addGestureRecognizer(swipeDown)

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Done"
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.2)
        configuration.baseForegroundColor = .white
        let done = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.close() })
        done.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(done)
        NSLayoutConstraint.activate([
            done.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            done.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
    }

    override var prefersStatusBarHidden: Bool { true }

    override func accessibilityPerformEscape() -> Bool {
        close()
        return true
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    /// Zooms in on the point tapped, or back out.
    @objc private func toggleZoom(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let point = recognizer.location(in: imageView)
        let scale = min(scrollView.maximumZoomScale, 2.5)
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                   width: size.width, height: size.height), animated: true)
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func swipeToClose() {
        // Swiping down while zoomed pans the picture instead.
        guard scrollView.zoomScale <= scrollView.minimumZoomScale else { return }
        close()
    }
}
