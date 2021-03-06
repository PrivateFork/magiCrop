//
//  Home.swift
//  GrabCutIOS
//
//  Created by Noah Gallant on 7/6/17.
//  Copyright © 2017 EunchulJeon. All rights reserved.
//

import UIKit
import Foundation
import Vision
import ImageIO
import CoreML

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @IBOutlet weak var imageView: UIImageView!
    
    @IBOutlet weak var pages: UIScrollView!
    
    @IBOutlet weak var loader: UIActivityIndicatorView!
    @IBOutlet weak var drawView: DrawableView!
    
    var _rectangles: [CGRect]!
    var _faces: [UIImage]!
    var _cuts: [UIImage]!
    var _image: UIImage!
    var _cimage: CIImage!
    var _transform: UIImage!
    var _orientation: CGImagePropertyOrientation!
    
    let yolo = YOLO()
    
    let maskView = UIImageView()
    
    var request: VNCoreMLRequest!
    var startTime: CFTimeInterval = 0
    
    
    let ciContext = CIContext()
    var resizedPixelBuffer: CVPixelBuffer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpCoreImage()
    }
    
    func setUpCoreImage() {
        let status = CVPixelBufferCreate(nil, YOLO.inputWidth, YOLO.inputHeight,
                                         kCVPixelFormatType_32BGRA, nil,
                                         &resizedPixelBuffer)
        if status != kCVReturnSuccess {
            print("Error: could not create resized pixel buffer", status)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
    
    @IBAction func takePicture(_ sender: Any) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        present(picker, animated: true)
    }
    @IBAction func chooseImage(_ sender: Any) {
        // The photo library is the default source, editing not allowed
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .savedPhotosAlbum
        present(picker, animated: true)
    }
    
    var inputImage: CIImage! // The image to be processed.
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        picker.dismiss(animated: true)
        
        guard let uiImage = info[UIImagePickerControllerOriginalImage] as? UIImage
            else { fatalError("no image from image picker") }
        guard let ciImage = CIImage(image: uiImage)
            else { fatalError("can't create CIImage from UIImage") }
        let orientation = CGImagePropertyOrientation(rawValue: UInt32(uiImage.imageOrientation.rawValue))
        inputImage = ciImage.applyingOrientation(Int32(orientation!.rawValue))
        
        imageView.image = uiImage
        
        _image = uiImage
        _cimage = ciImage
        _orientation = orientation
    }
    
    func drawRectangleOnImage(image: UIImage, rectangle: CGRect) -> UIImage {
        let imageSize = image.size
        let scale: CGFloat = 0
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        
        image.draw(at: CGPoint())
        
        UIColor.red.setStroke()
        UIRectFrame(rectangle)
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage!
    }
    
    func grabCutFaces(){ //GrabCut function takes face rectangles generated by rectanglesRequest and cuts out the faces
        let gb = GrabCutWrapper()
        _faces = []
        var i = 0
        for rect in _rectangles{
            print(rect)
            let m = gb.doGrabcut(_cuts[i], foregroundBound: rect)
            if let f = gb.masking(_cuts[i], mask: m){
                _faces.append(f)
            }
            i+=1
        }
        DispatchQueue.main.async {
            //let rect = self._rectangles[0]
            //self.imageView.image = self.drawRectangleOnImage(image: self._transform, rectangle: rect)
            self.pages.contentSize = CGSize(width: CGFloat(Double(self._faces.count)*Double(self.pages.bounds.size.width)), height: self.pages.bounds.size.height)
            
            
            for p in self.pages.subviews{
                p.removeFromSuperview()
            }
            
            let containerView = UIView(frame: CGRect(x: 0, y: 0, width: CGFloat(Double(self._faces.count)*Double(self.pages.bounds.size.width)), height: self.pages.bounds.size.height))
            
            var i = 0.0
            
            for face in self._faces{
                let iV = UIImageView()
                iV.image = face
                iV.frame = CGRect(x: CGFloat(i*Double(self.pages.bounds.size.width)), y: 0, width: self.pages.bounds.size.width, height: self.pages.bounds.size.height)
                iV.isUserInteractionEnabled = true
                //iV.backgroundColor = UIColor.red
                containerView.addSubview(iV)
                i+=1
            }
            
            self.pages.addSubview(containerView)
            
        }
        
        DispatchQueue.main.async {
            self.loader.stopAnimating()
        }
    }
    
    
    
    func convRect(rect: CGRect) -> CGRect{
        return CGRect(x: rect.origin.x*self._image.size.width, y: rect.origin.y*self._image.size.height, width: rect.width*self._image.size.width, height: rect.height*self._image.size.height)
    }
    
    func padRect(rect: CGRect, x: CGFloat, y: CGFloat) -> CGRect{
        return CGRect(x: rect.origin.x-(x-1)/2*rect.width, y: rect.origin.y-(y-1)/2*rect.height, width: x*rect.width, height: y*rect.height)
    }
    
    lazy var rectanglesRequest: VNDetectFaceRectanglesRequest = {
        return VNDetectFaceRectanglesRequest(completionHandler: self.handleRectangles)
    }()
    
    func handleRectangles(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNFaceObservation]
            else { fatalError("unexpected result type from VNDetectRectanglesRequest") }
        
        _rectangles = []
        _cuts = []
        
        for d in observations{
            _rectangles.append(padRect(rect: convRect(rect: d.boundingBox), x:1.25, y:2))
            _cuts.append(_image)
        }
        print(_rectangles[0])
        DispatchQueue.main.async {
            self.imageView.image = self.drawRectangleOnImage(image: self._image, rectangle: self._rectangles[0])
        }
        _transform = _image
        self.grabCutFaces()
        
    }
    
    @IBAction func cropFace(){
        loader.startAnimating()
        
        // Run the rectangle detector, which upon completion runs the GrabCut
        let handler = VNImageRequestHandler(ciImage: _cimage, orientation: Int32(_orientation!.rawValue))
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                try handler.perform([self.rectanglesRequest])
            } catch {
                print(error)
            }
        }
    }
    
    @IBAction func cropObjects(){
        predict(image: _image)
    }
    
    func predict(image: UIImage) {
        if let pixelBuffer = image.pixelBuffer(width: 416, height: 416) {
            predict(pixelBuffer: pixelBuffer)
        }
    }
    
    func predict(pixelBuffer: CVPixelBuffer) {
        // Measure how long it takes to predict a single video frame.
        startTime = CACurrentMediaTime()
        
        // Resize the input with Core Image to 416x416.
        guard let resizedPixelBuffer = resizedPixelBuffer else { print("here")
            return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sx = CGFloat(YOLO.inputWidth) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let sy = CGFloat(YOLO.inputHeight) / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaleTransform = CGAffineTransform(scaleX: sx, y: sy)
        let scaledImage = ciImage.applying(scaleTransform)
        ciContext.render(scaledImage, to: resizedPixelBuffer)
        
        
        
        _transform = UIImage.init(ciImage: scaledImage)
        
        // This is an alternative way to resize the image (using vImage):
        //if let resizedPixelBuffer = resizePixelBuffer(pixelBuffer,
        //                                              width: YOLO.inputWidth,
        //                                              height: YOLO.inputHeight)
        
        // Resize the input to 416x416 and give it to our model.
        
        
        
        if let boundingBoxes = try? yolo.predict(image: resizedPixelBuffer) {
            _cuts = []
            _rectangles = []
            self.loader.startAnimating()
            var ct : UIImage = _transform.copy() as! UIImage
            for box in boundingBoxes{
                
                var r1 = padRect(rect: box.rect, x: 1.1, y: 1.1)
                let r2 = padRect(rect: r1, x: 1.1, y: 1.1)
                r1.origin = CGPoint(x: 0.05*r1.size.width, y: 0.05*r1.size.height)
                _rectangles.append(r1)
                let c = crop(image: _transform, cropRect: r2)
                _cuts.append(c!)
                
                ct = self.drawRectangleOnImage(image: ct, rectangle: box.rect)
            }
            
            self.imageView.image = ct
            //self.cutView.image = crop(image: _transform, cropRect: boundingBoxes[0].rect)
            
            self.grabCutFaces()
            
        }
            
        
    }
    
    
    func crop(image:UIImage, cropRect:CGRect) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(cropRect.size, false, image.scale)
        let origin = CGPoint(x: cropRect.origin.x * CGFloat(-1), y: cropRect.origin.y * CGFloat(-1))
        image.draw(at: origin)
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext();
        
        return result
    }
    
}
