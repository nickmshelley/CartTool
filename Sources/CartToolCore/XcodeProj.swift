//
//  XcodeProj.swift
//
//  Created by Bart Whiteley on 1/28/18.
//  Copyright (c) 2018 Ancestry.com. All rights reserved.
//

import Foundation
import xcproj

/**
 This is intended to be executed as a Run Script build phase in Xcode.
 Extracts the list of frameworks from the compiled app using otool.
 Searches for each framework in FRAMEWORK_SEARCH_PATHS.
 Sets up input and output environment variables for each framework, and invokes `carthage copy-frameworks`.
 
 throws: String error if carthage is not installed or an expected environment variable is missing.
 */
func wrapCarthageCopyFrameworks(platform: String?) throws {
    guard let platform = platform else { throw "platform not specified for copy-frameworks" }
    guard ishell("which", "carthage") == 0 else {
        throw "carthage executable not found"
    }
    
    let builtProductsDir = try getEnv("BUILT_PRODUCTS_DIR")
    let frameworksFolderPath = try getEnv("FRAMEWORKS_FOLDER_PATH")
    let projectPath = try getEnv("PROJECT_DIR")
    let executableName = try getEnv("EXECUTABLE_NAME")
    let appName = executableName + ".app"
    let appPath = Path(builtProductsDir)
        .pathByAppending(component: appName)
        .pathByAppending(component: executableName)
    let frameworksPath = Path(projectPath)
        .pathByAppending(component: "Carthage/Build")
        .pathByAppending(component: platform)
    let frameworksTargetDir = Path(builtProductsDir).pathByAppending(component: frameworksFolderPath)
    
    let dependencies = Set(getDependencies(appPath: appPath, frameworksPath: frameworksPath))
    let inputs = try resolve(frameworks: Array(dependencies))
    let outputs = dependencies.map {
        frameworksTargetDir.pathByAppending(component: $0).absolute
    }
    
    print("Resolved frameworks for `carthage copy-frameworks`:")
    inputs.forEach { print($0) }
    
    var env: [String: String] = ProcessInfo.processInfo.environment
    let inputsOutputs = zip(inputs, outputs)
    
    for (idx, inOut) in inputsOutputs.enumerated() {
        let iKey = "SCRIPT_INPUT_FILE_\(idx)"
        env[iKey] = inOut.0
        let oKey = "SCRIPT_OUTPUT_FILE_\(idx)"
        env[oKey] = inOut.1
    }
    let countString = String(inputs.count)
    env["SCRIPT_INPUT_FILE_COUNT"] = countString
    env["SCRIPT_OUTPUT_FILE_COUNT"] = countString
    
    try shell(env: env, "carthage", "copy-frameworks")
}

private func getDependencies(appPath: Path, frameworksPath: Path) -> [String] {
    var frameworksToProcess = otool(path: appPath)
    var alreadyProcessed: Set<String> = []
    var allFrameworks = frameworksToProcess
    let fm = FileManager.default
    
    while !frameworksToProcess.isEmpty {
        guard let next = frameworksToProcess.popLast() else { break }
        guard !alreadyProcessed.contains(next) else { continue }
        
        let nextPath = frameworksPath.pathByAppending(component: next)
        guard fm.fileExists(atPath: nextPath.absolute) else {
            allFrameworks.removeAll { $0 == next }
            continue
        }
        
        alreadyProcessed.insert(next)
        let newFrameworks = otool(path: nextPath)
        frameworksToProcess += newFrameworks
        allFrameworks += newFrameworks
    }
    
    return allFrameworks
}

private func otool(path: Path) -> [String] {
    do {
        let output = try shellOutput("otool", "-L", path.absolute)
        let frameworks = output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { $0.components(separatedBy: "(").first! }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("@rpath") }
            .filter { !$0.contains("libswift") }
            .map { $0.replacingOccurrences(of: "@rpath/", with: "") }
        
        return frameworks
    } catch {
        print("Failed to get otool output from \(path)")
        return []
    }
}

private func frameworkNames(from paths: [Path]) -> [String] {
    return paths.compactMap { $0.baseName.components(separatedBy: ".").first }
}

/**
 Turn a space-delimited string into an array separated by spaces
 - parameter str: The input string
 - returns: Array of strings produced by splitting the input on spaces
 
 Note: spaces not intended to be used as separated should be escaped as "\\ "
 (this is how Xcode excapes spaces in path elements for environment variables such as FRAMEWORK_SEARCH_PATHS)
 */
internal func splitEnvVar(_ str: String) -> [String] {
    let escapedSpacePlaceholder: StringLiteralType = "_escaped_space_placeholder_"
    let tmp = str.replacingOccurrences(of: "\\ ", with: escapedSpacePlaceholder)
    return tmp.split(separator: " ").map(String.init).map { str in
        str.replacingOccurrences(of: escapedSpacePlaceholder, with: " ")
    }
}

/**
 Get an environment variable
 - parameter key: The name of the environment variable to retrieve
 - throws: String error if the variable is not found
 - returns: Value of the environment variable
 */
internal func getEnv(_ key: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[key] else {
        throw "Missing \(key) environment variable"
    }
    return value
}

/**
 Search for frameworks in FRAMEWORK_SEARCH_PATHS
 
 - parameter Frameworks: The list of framework names
 - throws: String error if a framework is not found in FRAMEWORK_SEARCH_PATHS
 - returns: Array of full paths to frameworks found in FRAMEWORK_SEARCH_PATHS
 */
internal func resolve(frameworks: [String]) throws -> [String] {
    let fm = FileManager.default
    let frameworkSearchPathsVar = try getEnv("FRAMEWORK_SEARCH_PATHS")
    let frameworkSearchPaths: [String] = splitEnvVar(frameworkSearchPathsVar)
    return try frameworks.map { framework in
        for path in frameworkSearchPaths {
            let fullFrameworkPath = Path(path).pathByAppending(component: framework).absolute
            if fm.fileExists(atPath: fullFrameworkPath) {
                return fullFrameworkPath
            }
        }
        throw "Unable to find \(framework) in FRAMEWORK_SEARCH_PATHS"
    }
}
