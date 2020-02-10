//
//  ViewController.swift
//  Rampage
//
//  Created by Nick Lockwood on 17/05/2019.
//  Copyright © 2019 Nick Lockwood. All rights reserved.
//

import UIKit
import Engine

private let joystickRadius: Double = 40
private let maximumTimeStep: Double = 1 / 20
private let worldTimeStep: Double = 1 / 120

public func loadLevels() -> [Tilemap] {
    let jsonURL = Bundle.main.url(forResource: "Levels", withExtension: "json")!
    let jsonData = try! Data(contentsOf: jsonURL)
    let levels = try! JSONDecoder().decode([MapData].self, from: jsonData)
    return levels.enumerated().map { Tilemap($0.element, index: $0.offset) }
}

public func loadTextures() -> Textures {
    return Textures(loader: { name in
        Bitmap(image: UIImage(named: name)!)!
    })
}

public extension SoundName {
    var url: URL? {
        return Bundle.main.url(forResource: rawValue, withExtension: "mp3")
    }
}

func setUpAudio() {
    for name in SoundName.allCases {
        precondition(name.url != nil, "Missing mp3 file for \(name.rawValue)")
    }
    try? SoundManager.shared.activate()
    _ = try? SoundManager.shared.preload(SoundName.allCases[0].url!)
}

class ViewController: UIViewController {
    private let contentView = ContentView()
    private let tapGesture = UITapGestureRecognizer()
    private let textures = loadTextures()
    private let levels =  loadLevels()
    private lazy var world = World(map: levels[0])
    private var lastFrameTime = CACurrentMediaTime()
    private var lastFiredTime = 0.0

    private var imageView: UIImageView {
        return contentView.imageView
    }

    override func loadView() {
        self.view = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if NSClassFromString("XCTestCase") != nil {
            return
        }

        setUpAudio()

        let displayLink = CADisplayLink(target: self, selector: #selector(update))
        displayLink.add(to: .main, forMode: .common)

        view.addGestureRecognizer(tapGesture)
        tapGesture.addTarget(self, action: #selector(fire))
        tapGesture.delegate = self
    }
    
    @objc func update(_ displayLink: CADisplayLink) {
        let timeStep = min(maximumTimeStep, displayLink.timestamp - lastFrameTime)
        let leftInputVector = contentView.leftJoystickInputVector
        let rightInputVector = contentView.rightJoystickInputVector
        
        let rotation = rightInputVector.x * world.player.turningSpeed * worldTimeStep
        let input = Input(
            speed: Vector(x: leftInputVector.x, y: -leftInputVector.y),
            rotation: Rotation(sine: sin(rotation), cosine: cos(rotation)),
            isFiring: lastFiredTime > lastFrameTime
        )
        let worldSteps = (timeStep / worldTimeStep).rounded(.up)
        for _ in 0 ..< Int(worldSteps) {
            if let action = world.update(timeStep: timeStep / worldSteps, input: input) {
                switch action {
                case .loadLevel(let index):
                    SoundManager.shared.clearAll()
                    let index = index % levels.count
                    world.setLevel(levels[index])
                case .playSounds(let sounds):
                    for sound in sounds {
                        DispatchQueue.main.asyncAfter(deadline: .now() + sound.delay) {
                            guard let url = sound.name?.url else {
                                if let channel = sound.channel {
                                    SoundManager.shared.clearChannel(channel)
                                }
                                return
                            }
                            try? SoundManager.shared.play(
                                url,
                                channel: sound.channel,
                                volume: sound.volume,
                                pan: sound.pan
                            )
                        }
                    }
                }
            }
        }
        lastFrameTime = displayLink.timestamp
        
        let width = Int(imageView.bounds.width), height = Int(imageView.bounds.height)
        var renderer = Renderer(width: width, height: height, textures: textures)
        renderer.draw(world)
        
        imageView.image = UIImage(bitmap: renderer.bitmap)
    }

    @objc func fire(_ gestureRecognizer: UITapGestureRecognizer) {
        lastFiredTime = CACurrentMediaTime()
    }
}

extension ViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}

class ContentView: UIView {
    
    private(set) lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.layer.magnificationFilter = .nearest
        return imageView
    }()
    
    private let leftJoyStick = UIView()
    private let rightJoystick = UIView()
    
    let leftGestureRecognizer = UIPanGestureRecognizer()
    let rightGestureRecognizer = UIPanGestureRecognizer()
    
    var leftJoystickInputVector: Vector {
        switch leftGestureRecognizer.state {
        case .began, .changed:
            let translation = leftGestureRecognizer.translation(in: self)
            var vector = Vector(x: Double(translation.x), y: Double(translation.y))
            vector /= max(joystickRadius, vector.length)
            leftGestureRecognizer.setTranslation(CGPoint(
                x: vector.x * joystickRadius,
                y: vector.y * joystickRadius
            ), in: self)
            return vector
        default:
            return Vector(x: 0, y: 0)
        }
    }
    
    var rightJoystickInputVector: Vector {
        switch rightGestureRecognizer.state {
        case .began, .changed:
            let translation = rightGestureRecognizer.translation(in: self)
            var vector = Vector(x: Double(translation.x), y: Double(translation.y))
            vector /= max(joystickRadius, vector.length)
            rightGestureRecognizer.setTranslation(CGPoint(
                x: vector.x * joystickRadius,
                y: vector.y * joystickRadius
            ), in: self)
            return vector
        default:
            return Vector(x: 0, y: 0)
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(imageView)
        addSubview(leftJoyStick)
        addSubview(rightJoystick)
        
        leftJoyStick.addGestureRecognizer(leftGestureRecognizer)
        rightJoystick.addGestureRecognizer(rightGestureRecognizer)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        let size = CGSize(width: bounds.width / 2, height: bounds.height)
        leftJoyStick.frame = CGRect(origin: .zero, size: size)
        rightJoystick.frame = CGRect(origin: CGPoint(x: size.width, y: 0), size: size)
        imageView.frame = bounds
    }
}
