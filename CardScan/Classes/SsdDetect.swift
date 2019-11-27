//
//  SsdDetect.swift
//  CardScan
//
//  Created by Zain on 8/5/19.
//

import Foundation
import os.log

/**
 Documentation on how SSD works
 
 */


@available(iOS 11.2, *)
public struct SsdDetect {
    static var ssdModel: SSD? = nil
    static var priors:[CGRect]? = nil
    
    // SSD Model Parameters
    static let SSDCardWidth = 300
    static let SSDCardHeight = 300
    static let probThreshold: Float = 0.3
    static let iouThreshold: Float = 0.45
    static let candidateSize = 200
    static let topK = 10

    /* We don't use the following constants, these values are determined at run time
    *  Regardless, this is good information to keep around.
    *  let NoOfClasses = 13
    *  let TotalNumberOfPriors = 2766
    *  let NoOfCordinates = 4
    */
    
    public private(set) var allSSDBoxes = DetectedAllBoxes()

    
    func warmUp() {

        UIGraphicsBeginImageContext(CGSize(width: SsdDetect.SSDCardWidth, height: SsdDetect.SSDCardHeight))
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: SsdDetect.SSDCardWidth, height: SsdDetect.SSDCardHeight))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let ssdModel = SsdDetect.ssdModel else {
            print("Models not initialized")
            return
        }
        
        if let pixelBuffer = newImage?.pixelBuffer(width: SsdDetect.SSDCardWidth, height: SsdDetect.SSDCardHeight) {
            let _ = try? ssdModel.prediction(_0: pixelBuffer)
        }
        
    }
    
    public init() {
        if SsdDetect.priors == nil {
            SsdDetect.priors = PriorsGen.combinePriors()
        }
        
    }
    
    public static func initializeModels(contentsOf url: URL) {
        if SsdDetect.ssdModel == nil {
            SsdDetect.ssdModel = try? SSD(contentsOf: url)
        }
        
    }
    
    public static func isModelLoaded() -> Bool {
        return self.ssdModel != nil
    }
    
    func detectObjects(prediction: SSDOutput, image: UIImage) -> DetectedAllBoxes {
        var DetectedSSDBoxes = DetectedAllBoxes()
        var startTime = CFAbsoluteTimeGetCurrent()
        let boxes = prediction.getBoxes()
        let scores = prediction.getScores()
        var endTime = CFAbsoluteTimeGetCurrent() - startTime
        os_log("%@", type: .debug, "Get boxes and scores from mult-array time: \(endTime)")
        
        startTime = CFAbsoluteTimeGetCurrent()
        let normalizedScores = prediction.fasterSoftmax2D(scores)
        let regularBoxes = prediction.convertLocationsToBoxes(locations: boxes, priors: SsdDetect.priors ?? PriorsGen.combinePriors(), centerVariance: 0.1, sizeVariance: 0.2)
        let cornerFormBoxes = prediction.centerFormToCornerForm(regularBoxes: regularBoxes)

        let predAPI = PredictionAPI()
        let result:Result = predAPI.predictionAPI(scores:normalizedScores, boxes: cornerFormBoxes, probThreshold: SsdDetect.probThreshold, iouThreshold: SsdDetect.iouThreshold, candidateSize: SsdDetect.candidateSize, topK: SsdDetect.topK)
        endTime = CFAbsoluteTimeGetCurrent() - startTime
        os_log("%@", type: .debug, "Rest of the forward pass time: \(endTime)")
        
        for idx in 0..<result.pickedBoxes.count {
            DetectedSSDBoxes.allBoxes.append(DetectedSSDBox(category: result.pickedLabels[idx], conf: result.pickedBoxProbs[idx], XMin: Double(result.pickedBoxes[idx][0]), YMin: Double(result.pickedBoxes[idx][1]), XMax: Double(result.pickedBoxes[idx][2]), YMax: Double(result.pickedBoxes[idx][3]), imageSize: image.size))
        }


       return DetectedSSDBoxes
        
    }
    
    
    public mutating func predict(image: UIImage) -> String? {

        guard let pixelBuffer = image.pixelBuffer(width: SsdDetect.SSDCardWidth, height: SsdDetect.SSDCardHeight) else {
            os_log("Couldn't convert to pixel buffer", type: .debug)
            return nil
        }
        
        
        guard let detectModel = SsdDetect.ssdModel else {
            os_log("Model not initialized", type: .debug)
            return nil
        }
       
        let startTime = CFAbsoluteTimeGetCurrent()
        guard let prediction = try? detectModel.prediction(_0: pixelBuffer) else {
            os_log("Couldn't predict", type: .debug)
            return nil
        }
        let endTime = CFAbsoluteTimeGetCurrent() - startTime
        os_log("%@", type: .debug, "Model Run without post-process time: \(endTime)")

        self.allSSDBoxes = self.detectObjects(prediction: prediction, image: image)
        return "Sucess"
    }
    

}
