//
//  ContentView.swift
//  MaterialsExample
//
//  Created by Nien Lam on 9/27/21.
//  Copyright © 2021 Line Break, LLC. All rights reserved.
//

import SwiftUI
import ARKit
import RealityKit
import Combine


// MARK: - View model for handling communication between the UI and ARView.
class ViewModel: ObservableObject {
    let uiSignal = PassthroughSubject<UISignal, Never>()
    
    @Published var positionLocked = false
    
    enum UISignal {
        case lockPosition
    }
}


// MARK: - UI Layer.
struct ContentView : View {
    @StateObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            // AR View.
            ARViewContainer(viewModel: viewModel)
            
            // Lock release button.
            Button {
                viewModel.uiSignal.send(.lockPosition)
            } label: {
                Label("Lock Position", systemImage: "target")
                    .font(.system(.title))
                    .foregroundColor(.white)
                    .labelStyle(IconOnlyLabelStyle())
                    .frame(width: 44, height: 44)
                    .opacity(viewModel.positionLocked ? 0.25 : 1.0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.bottom, 30)
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }
}


// MARK: - AR View.
struct ARViewContainer: UIViewRepresentable {
    let viewModel: ViewModel
    
    func makeUIView(context: Context) -> ARView {
        SimpleARView(frame: .zero, viewModel: viewModel)
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

class SimpleARView: ARView {
    var viewModel: ViewModel
    var arView: ARView { return self }
    var originAnchor: AnchorEntity!
    var subscriptions = Set<AnyCancellable>()
    
    // Empty entity for cursor.
    var cursor: Entity!
    
    // Scene lights.
    var directionalLight: DirectionalLight!

    init(frame: CGRect, viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(frame: frame)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        setupScene()
        
        setupEntities()
    }
    
    func setupScene() {
        // Setup world tracking and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]
        arView.session.run(configuration)
        
        // Called every frame.
        scene.subscribe(to: SceneEvents.Update.self) { event in
            if !self.viewModel.positionLocked {
                self.updateCursor()
            }
        }.store(in: &subscriptions)
        
        // Process UI signals.
        viewModel.uiSignal.sink { [weak self] in
            self?.processUISignal($0)
        }.store(in: &subscriptions)
    }
    
    // Hide/Show active tetromino & process controls.
    func processUISignal(_ signal: ViewModel.UISignal) {
        switch signal {
        case .lockPosition:
            viewModel.positionLocked.toggle()
        }
    }
    
    // Move cursor to plane detected.
    func updateCursor() {
        // Raycast to get cursor position.
        let results = raycast(from: center,
                              allowing: .existingPlaneGeometry,
                              alignment: .any)
        
        // Move cursor to position if hitting plane.
        if let result = results.first {
            cursor.isEnabled = true
            cursor.move(to: result.worldTransform, relativeTo: originAnchor)
        } else {
            cursor.isEnabled = false
        }
    }
    
    func setupEntities() {
        // Create an anchor at scene origin.
        originAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(originAnchor)
        
        // Create and add empty cursor entity to origin anchor.
        cursor = Entity()
        originAnchor.addChild(cursor)
        
        // Add directional light.
        directionalLight = DirectionalLight()
        directionalLight.light.intensity = 1000
        directionalLight.look(at: [0,0,0], from: [1, 1.1, 1.3], relativeTo: originAnchor)
        directionalLight.shadow = DirectionalLightComponent.Shadow(maximumDistance: 0.5, depthBias: 2)
        originAnchor.addChild(directionalLight)

        // Add checkerboard plane.
        var checkerBoardMaterial = PhysicallyBasedMaterial()
        checkerBoardMaterial.baseColor.texture = .init(try! .load(named: "checker-board.png"))
        let checkerBoardPlane = ModelEntity(mesh: .generatePlane(width: 0.5, depth: 0.5), materials: [checkerBoardMaterial])
        cursor.addChild(checkerBoardPlane)


        // Array or spheres with different material properties.

        let sphereSize: Float = 0.03
        
        for roughnessStep in 0...2 {
            // Increment roughness.
            let roughness = Float(roughnessStep) * 0.5

            for metallicStep in 0...2 {
                // Increment metallic.
                let metallic = Float(metallicStep) * 0.5

                // Vary roughness and metallic.
                var material = PhysicallyBasedMaterial()
                material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .purple)
                material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: roughness)
                material.metallic  = PhysicallyBasedMaterial.Metallic(floatLiteral: metallic)
                
                // Position sphere in a grid.
                let sphereEntity = ModelEntity(mesh: .generateSphere(radius: sphereSize), materials: [material])
                sphereEntity.position.y = sphereSize
                sphereEntity.position.x = Float(roughnessStep) * sphereSize * 2
                sphereEntity.position.z = Float(metallicStep) * sphereSize * 2
             
                checkerBoardPlane.addChild(sphereEntity)
            }
        }

    }
}
