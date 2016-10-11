//
//  TextNode.swift
//  TGUIKit
//
//  Created by keepcoder on 10/09/16.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa

private let defaultFont = systemFont(13)

private final class TextNodeLine {
    let line: CTLine
    let frame: CGRect
    
    init(line: CTLine, frame: CGRect) {
        self.line = line
        self.frame = frame
    }
}

public enum TextNodeCutoutPosition {
    case TopLeft
    case TopRight
}

public struct TextNodeCutout: Equatable {
    public let position: TextNodeCutoutPosition
    public let size: NSSize
}

public func ==(lhs: TextNodeCutout, rhs: TextNodeCutout) -> Bool {
    return lhs.position == rhs.position && lhs.size == rhs.size
}

public final class TextNodeLayout: NSObject {
    fileprivate let attributedString: NSAttributedString?
    fileprivate let maximumNumberOfLines: Int
    fileprivate let truncationType: CTLineTruncationType
    fileprivate let backgroundColor: NSColor?
    fileprivate let constrainedSize: NSSize
    fileprivate let cutout: TextNodeCutout?
    public let size: NSSize
    fileprivate let lines: [TextNodeLine]
    public var selected:Bool = false
    
    fileprivate init(attributedString: NSAttributedString?, maximumNumberOfLines: Int, truncationType: CTLineTruncationType, constrainedSize: NSSize, cutout: TextNodeCutout?, size: NSSize, lines: [TextNodeLine], backgroundColor: NSColor?) {
        self.attributedString = attributedString
        self.maximumNumberOfLines = maximumNumberOfLines
        self.truncationType = truncationType
        self.constrainedSize = constrainedSize
        self.cutout = cutout
        self.size = size
        self.lines = lines
        self.backgroundColor = backgroundColor
    }
    
    var numberOfLines: Int {
        return self.lines.count
    }
    
    var trailingLineWidth: CGFloat {
        if let lastLine = self.lines.last {
            return lastLine.frame.width
        } else {
            return 0.0
        }
    }
}

public class TextNode: NSObject {
    private var currentLayout: TextNodeLayout?
    public var backgroundColor:NSColor
    public override init() {
        self.backgroundColor = NSColor.red
        super.init()
    }
    
    
    private class func getlayout(attributedString: NSAttributedString?, maximumNumberOfLines: Int, truncationType: CTLineTruncationType, backgroundColor: NSColor?, constrainedSize: NSSize, cutout: TextNodeCutout?, selected:Bool) -> TextNodeLayout {
        
        var attr = attributedString
        
        if let a = attr {
            if (selected && a.length > 0) {
                
                var c:NSMutableAttributedString = a.mutableCopy() as! NSMutableAttributedString
                
                if let color = c.attribute(kSelectedColorAttribute, at: 0, effectiveRange: nil) {
                    c.addAttribute(NSForegroundColorAttributeName, value: color, range: c.range)
                }
                
                attr = c
                
            }

        }
        
        
        if let attributedString = attr {
            

            let font: CTFont
            if attributedString.length != 0 {
                if let stringFont = attributedString.attribute(kCTFontAttributeName as String, at: 0, effectiveRange: nil) {
                    font = stringFont as! CTFont
                } else {
                    font = defaultFont
                }
            } else {
                font = defaultFont
            }
            
            let fontAscent = CTFontGetAscent(font)
            let fontDescent = CTFontGetDescent(font)
            let fontLineHeight = floor(fontAscent + fontDescent)
            let fontLineSpacing = floor(fontLineHeight * 0.12)
            
            var lines: [TextNodeLine] = []
            
           
            
            var maybeTypesetter: CTTypesetter?
            maybeTypesetter = CTTypesetterCreateWithAttributedString(attributedString as CFAttributedString)
            if maybeTypesetter == nil {
                return TextNodeLayout(attributedString: attributedString, maximumNumberOfLines: maximumNumberOfLines, truncationType: truncationType, constrainedSize: constrainedSize, cutout: cutout, size: NSSize(), lines: [], backgroundColor: backgroundColor)
            }
            
            let typesetter = maybeTypesetter!
            
            var lastLineCharacterIndex: CFIndex = 0
            var layoutSize = NSSize()
            
            var cutoutEnabled = false
            var cutoutMinY: CGFloat = 0.0
            var cutoutMaxY: CGFloat = 0.0
            var cutoutWidth: CGFloat = 0.0
            var cutoutOffset: CGFloat = 0.0
            if let cutout = cutout {
                cutoutMinY = -fontLineSpacing
                cutoutMaxY = cutout.size.height + fontLineSpacing
                cutoutWidth = cutout.size.width
                if case .TopLeft = cutout.position {
                    cutoutOffset = cutoutWidth
                }
                cutoutEnabled = true
            }
            
            var first = true
            while true {
                var lineConstrainedWidth = constrainedSize.width
                var lineOriginY = floor(layoutSize.height + fontLineHeight - fontLineSpacing * 2.0)
                if !first {
                    lineOriginY += fontLineSpacing
                }
                var lineCutoutOffset: CGFloat = 0.0
                var lineAdditionalWidth: CGFloat = 0.0
                
                if cutoutEnabled {
                    if lineOriginY < cutoutMaxY && lineOriginY + fontLineHeight > cutoutMinY {
                        lineConstrainedWidth = max(1.0, lineConstrainedWidth - cutoutWidth)
                        lineCutoutOffset = cutoutOffset
                        lineAdditionalWidth = cutoutWidth
                    }
                }
                
                let lineCharacterCount = CTTypesetterSuggestLineBreak(typesetter, lastLineCharacterIndex, Double(lineConstrainedWidth))
                
                if maximumNumberOfLines != 0 && lines.count == maximumNumberOfLines - 1 && lineCharacterCount > 0 {
                    if first {
                        first = false
                    } else {
                        layoutSize.height += fontLineSpacing
                    }
                    
                    let coreTextLine: CTLine
                    
                    let originalLine = CTTypesetterCreateLineWithOffset(typesetter, CFRange(location: lastLineCharacterIndex, length: attributedString.length - lastLineCharacterIndex), 0.0)
                    
                    if CTLineGetTypographicBounds(originalLine, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(originalLine) < Double(constrainedSize.width) {
                        coreTextLine = originalLine
                    } else {
                        var truncationTokenAttributes: [String : AnyObject] = [:]
                        truncationTokenAttributes[kCTFontAttributeName as String] = font
                        truncationTokenAttributes[kCTForegroundColorFromContextAttributeName as String] = true as NSNumber
                        let tokenString = "\u{2026}"
                        let truncatedTokenString = NSAttributedString(string: tokenString, attributes: truncationTokenAttributes)
                        let truncationToken = CTLineCreateWithAttributedString(truncatedTokenString)
                        
                        coreTextLine = CTLineCreateTruncatedLine(originalLine, Double(constrainedSize.width), truncationType, truncationToken) ?? truncationToken
                    }
                    
                    let lineWidth = ceil(CGFloat(CTLineGetTypographicBounds(coreTextLine, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(coreTextLine)))
                    let lineFrame = CGRect(x: lineCutoutOffset, y: lineOriginY, width: lineWidth, height: fontLineHeight)
                    layoutSize.height += fontLineHeight + fontLineSpacing
                    layoutSize.width = max(layoutSize.width, lineWidth + lineAdditionalWidth)
                    
                    lines.append(TextNodeLine(line: coreTextLine, frame: lineFrame))
                    
                    break
                } else {
                    if lineCharacterCount > 0 {
                        if first {
                            first = false
                        } else {
                            layoutSize.height += fontLineSpacing
                        }
                        
                        let coreTextLine = CTTypesetterCreateLineWithOffset(typesetter, CFRangeMake(lastLineCharacterIndex, lineCharacterCount), 100.0)
                        lastLineCharacterIndex += lineCharacterCount
                        
                        let lineWidth = ceil(CGFloat(CTLineGetTypographicBounds(coreTextLine, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(coreTextLine)))
                        let lineFrame = CGRect(x: lineCutoutOffset, y: lineOriginY, width: lineWidth, height: fontLineHeight)
                        layoutSize.height += fontLineHeight
                        layoutSize.width = max(layoutSize.width, lineWidth + lineAdditionalWidth)
                        
                       
                        
                        lines.append(TextNodeLine(line: coreTextLine, frame: lineFrame))
                    } else {
                        if !lines.isEmpty {
                            layoutSize.height += fontLineSpacing
                        }
                        break
                    }
                }
            }
            
            return TextNodeLayout(attributedString: attributedString, maximumNumberOfLines: maximumNumberOfLines, truncationType: truncationType, constrainedSize: constrainedSize, cutout: cutout, size: NSSize(width: ceil(layoutSize.width), height: ceil(layoutSize.height)), lines: lines, backgroundColor: backgroundColor)
        } else {
            return TextNodeLayout(attributedString: attributedString, maximumNumberOfLines: maximumNumberOfLines, truncationType: truncationType, constrainedSize: constrainedSize, cutout: cutout, size: NSSize(), lines: [], backgroundColor: backgroundColor)
        }
    }
    

    open func draw(_ dirtyRect: NSRect, in ctx: CGContext) {
       
        //let contextPtr = NSGraphicsContext.current()?.graphicsPort
        let context:CGContext = ctx //unsafeBitCast(contextPtr, to: CGContext.self)
        
        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(!System.isRetina)
        context.setAllowsFontSmoothing(!System.isRetina)
        
        
        if let layout = self.currentLayout {
            
            context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)

            
            let bg = backgroundColor ?? NSColor.white
           // context.setBlendMode(.copy)
           // context.setFillColor(bg.cgColor)
          //  context.fill(dirtyRect)
            
            let textMatrix = context.textMatrix
            let textPosition = context.textPosition
            
            
            
            for i in 0 ..< layout.lines.count {
                let line = layout.lines[i]
                context.textPosition = CGPoint(x: line.frame.origin.x + NSMinX(dirtyRect), y: line.frame.origin.y + NSMinY(dirtyRect))
                CTLineDraw(line.line, context)
                
            }
            
            context.textMatrix = textMatrix
            context.textPosition = CGPoint(x: textPosition.x, y: textPosition.y)
        }
        
      //  context.setBlendMode(.normal)
    }
    
     open class func layoutText(_ maybeNode: TextNode?) -> (_ attributedString: NSAttributedString?, _ backgroundColor: NSColor?, _ maximumNumberOfLines: Int, _ truncationType: CTLineTruncationType, _ constrainedSize: NSSize, _ cutout: TextNodeCutout?,_ selected:Bool ) -> (TextNodeLayout, () -> TextNode) {
        let existingLayout: TextNodeLayout? = maybeNode?.currentLayout
        
        return { attributedString, backgroundColor, maximumNumberOfLines, truncationType, constrainedSize, cutout, selected in
            let layout: TextNodeLayout
            
            var updated = false
            if let existingLayout = existingLayout, existingLayout.constrainedSize == constrainedSize && existingLayout.maximumNumberOfLines == maximumNumberOfLines && existingLayout.truncationType == truncationType && existingLayout.cutout == cutout && existingLayout.selected == selected {
                let stringMatch: Bool
                if let existingString = existingLayout.attributedString, let string = attributedString {
                    stringMatch = existingString.isEqual(to: string)
                } else if existingLayout.attributedString == nil && attributedString == nil {
                    stringMatch = true
                } else {
                    stringMatch = false
                }
                
                if stringMatch {
                    layout = existingLayout
                } else {
                    layout = TextNode.getlayout(attributedString: attributedString, maximumNumberOfLines: maximumNumberOfLines, truncationType: truncationType, backgroundColor: backgroundColor, constrainedSize: constrainedSize, cutout: cutout,selected:selected)
                    updated = true
                }
            } else {
                layout = TextNode.getlayout(attributedString: attributedString, maximumNumberOfLines: maximumNumberOfLines, truncationType: truncationType, backgroundColor: backgroundColor, constrainedSize: constrainedSize, cutout: cutout,selected:selected)
                updated = true
            }
            
            let node = maybeNode ?? TextNode()
            return (layout, {
                node.currentLayout = layout
                return node
            })
        }
    }
}
