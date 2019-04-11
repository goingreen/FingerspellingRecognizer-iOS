//
//  HandTracker.swift
//  Fingerspelling recognizer
//
//  Created by Artur Antonov on 11/04/2019.
//  Copyright © 2019 aa. All rights reserved.
//

import CoreGraphics
import CoreVideo

class HandTracker {

    var automatic: Bool = true

    func handRect(in depthPixelBuffer: CVPixelBuffer, depthCutOff: Float) -> (rect: CGRect, minDepth: Float) {
        guard automatic else {
            let handRect = CGRect(x: 20, y: 160, width: 320, height: 320)
            let minDepth = minimalDepth(depthPixelBuffer: depthPixelBuffer, rect: handRect)
            return (rect: handRect, minDepth: minDepth)
        }
        let depthWidth = CVPixelBufferGetWidth(depthPixelBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthPixelBuffer)

        let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthPixelBuffer)

        var minsHeap = Heap<(Float, Int)>(sort: { return $0.0 > $1.0})

        for yMap in 0 ..< depthHeight {
            let rowData = baseAddress + yMap * bytesPerRow
            let data = UnsafeMutableBufferPointer<Float32>(start: rowData.assumingMemoryBound(to: Float32.self), count: depthWidth)
            for index in 0 ..< depthWidth {
                if minsHeap.count < 4 {
                    minsHeap.insert((data[index], yMap * depthWidth + index))
                } else if data[index] < minsHeap.peek()!.0 {
                    minsHeap.replace(index: 0, value: (data[index], yMap * depthWidth + index))
                }
            }
        }

        let (minDepth, mini) = minsHeap.peek()!
        let startPoint: (Int, Int) = (mini - (mini/depthWidth) * depthWidth, mini/depthWidth)
        let cutOff = minDepth + depthCutOff
        var pointsToExplore: [(Int, Int)] = [startPoint]
        var used = [[Bool]](repeating: [Bool](repeating: false, count: depthHeight), count: depthWidth)
        used[startPoint.0][startPoint.1] = true
        var minX = startPoint.0
        var maxX = startPoint.0
        var minY = startPoint.1
        var maxY = startPoint.1

        func depthData(at point: (Int, Int)) -> Float {
            let rowData = baseAddress + point.1 * bytesPerRow
            let data = UnsafeMutableBufferPointer<Float32>(start: rowData.assumingMemoryBound(to: Float32.self), count: depthWidth)
            return data[point.0]
        }

        while !pointsToExplore.isEmpty {
            let point = pointsToExplore.remove(at: 0)
            minX = min(minX, point.0)
            maxX = max(maxX, point.0)
            minY = min(minY, point.1)
            maxY = max(maxY, point.1)
            var neighbours: [(Int, Int)] = []
            if point.0 > 0 {
                if !used[point.0 - 1][point.1] {
                    used[point.0 - 1][point.1] = true
                    neighbours.append((point.0 - 1, point.1))
                }
            }
            if point.0 < depthWidth - 1 {
                if !used[point.0 + 1][point.1] {
                    used[point.0 + 1][point.1] = true
                    neighbours.append((point.0 + 1, point.1))
                }
            }
            if point.1 > 0 {
                if !used[point.0][point.1 - 1] {
                    used[point.0][point.1 - 1] = true
                    neighbours.append((point.0, point.1 - 1))
                }
            }
            if point.1 < depthHeight - 1 {
                if !used[point.0][point.1 + 1] {
                    used[point.0][point.1 + 1] = true
                    neighbours.append((point.0, point.1 + 1))
                }
            }

            for neighbour in neighbours {
                if depthData(at: neighbour) < cutOff {
                    pointsToExplore.append(neighbour)
                }
            }
        }

        var handRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -10, dy: -10)
            .intersection(CGRect(x: 0, y: 0, width: depthWidth, height: depthHeight))
        if handRect.height/handRect.width > 1.5 {
            handRect.size.height = (1.5 * handRect.width).rounded()
        }
        
        return (rect: handRect, minDepth: minDepth)
    }

    private func minimalDepth(depthPixelBuffer: CVPixelBuffer, rect: CGRect) -> Float {
        let depthWidth = CVPixelBufferGetWidth(depthPixelBuffer)

        let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthPixelBuffer)

        var min = Float.greatestFiniteMagnitude
        for yMap in Int(rect.minY) ..< Int(rect.maxY) {
            let rowData = baseAddress + yMap * bytesPerRow
            let data = UnsafeMutableBufferPointer<Float32>(start: rowData.assumingMemoryBound(to: Float32.self), count: depthWidth)
            for index in Int(rect.minX) ..< Int(rect.maxX) {
                if data[index] < min {
                    min = data[index]
                }
            }
        }
        return min
    }
}
