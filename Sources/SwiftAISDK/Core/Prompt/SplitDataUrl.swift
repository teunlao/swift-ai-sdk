import Foundation

/**
 Splits a Data URL into its media type and base64 content components.

 Port of `@ai-sdk/ai/src/prompt/split-data-url.ts`.

 Data URLs have the format: `data:[<mediatype>][;base64],<data>`

 - Parameter dataUrl: The Data URL string to parse
 - Returns: A tuple containing the optional media type and base64 content

 ## Example
 ```swift
 let result = splitDataUrl("data:image/png;base64,iVBORw0KGgo...")
 // result.mediaType == "image/png"
 // result.base64Content == "iVBORw0KGgo..."
 ```
 */
public func splitDataUrl(_ dataUrl: String) -> (mediaType: String?, base64Content: String?) {
    do {
        let components = dataUrl.split(separator: ",", maxSplits: 1)
        guard components.count == 2 else {
            return (nil, nil)
        }

        let header = String(components[0])
        let base64Content = String(components[1])

        // Extract media type from header (format: "data:image/png;base64")
        let headerParts = header.split(separator: ";")
        guard let firstPart = headerParts.first else {
            return (nil, nil)
        }

        let dataParts = firstPart.split(separator: ":")
        guard dataParts.count == 2 else {
            return (nil, nil)
        }

        let mediaType = String(dataParts[1])
        return (mediaType, base64Content)
    } catch {
        return (nil, nil)
    }
}
