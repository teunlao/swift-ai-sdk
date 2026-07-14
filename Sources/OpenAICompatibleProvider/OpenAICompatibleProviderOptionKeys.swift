import AISDKProvider

func openAICompatibleCamelCase(_ value: String) -> String {
    var result = ""
    var index = value.startIndex

    while index < value.endIndex {
        let character = value[index]
        let nextIndex = value.index(after: index)

        if character == "-" || character == "_",
           nextIndex < value.endIndex {
            let nextCharacter = value[nextIndex]
            if nextCharacter >= "a", nextCharacter <= "z" {
                result.append(contentsOf: nextCharacter.uppercased())
                index = value.index(after: nextIndex)
                continue
            }
        }

        result.append(character)
        index = nextIndex
    }

    return result
}

func openAICompatibleDeprecatedProviderOptionsWarning(
    rawName: String,
    providerOptions: SharedV4ProviderOptions?
) -> SharedV4Warning? {
    let camelCaseName = openAICompatibleCamelCase(rawName)
    guard camelCaseName != rawName, providerOptions?[rawName] != nil else {
        return nil
    }

    return .deprecated(
        setting: "providerOptions key '\(rawName)'",
        message: "Use '\(camelCaseName)' instead."
    )
}
