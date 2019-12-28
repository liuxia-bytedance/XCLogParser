// Copyright (c) 2019 Spotify AB.
//
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import Foundation

extension IDEActivityLogSection {

    /// Returns the name of the target inside the `commandDetailDesc`
    /// - returns: The name of the target or nil if there is no target name in `commandDetailDesc`
    func getTargetFromCommand() -> String? {
        guard let startIndex = commandDetailDesc.range(of: "in target '"),
            let endIndex = commandDetailDesc.range(of: "' from project '") else {
                return nil
        }
        return String(commandDetailDesc[startIndex.upperBound..<endIndex.lowerBound])
    }

    /// Returns the Log with the subsections grouped in their Target
    ///
    /// Since Xcode 11, logs generated by xcodebuild have a flat structure, meaning that the steps
    /// are not grouped in Target sections. The only way to get the name of the target that a file belongs to
    /// is to parse the string `(in target 'ABC' from project Project)`.
    ///
    /// - returns An `IDEActivityLogSection` in which the subsections is an array of Targets and each one has
    /// an array of steps belonging to that target
    func groupedByTarget() -> IDEActivityLogSection {
        // The only way to know if the structure is flatten is to check the first elements
        // for the `(in target 'ABC' from project Project)` string
        let firstElements = subSections.prefix(15) // we only analyze up to the first 15 subsections
        let isFlatten = firstElements.contains { $0.getTargetFromCommand() != nil }
        if isFlatten {
            let mainTarget = "$MainTarget"
            let targetsDictionary = subSections.reduce(
                [String: IDEActivityLogSection]()) { targets, subSection -> [String: IDEActivityLogSection] in
                // some substeps belong to the root project, we use a fixed name for them
                let targetName = subSection.getTargetFromCommand() ?? mainTarget
                let target = getOrBuildTarget(targetName, in: targets, using: subSection)
                target.subSections.append(subSection)
                var updatedTargets = targets
                updatedTargets[targetName] = target
                return updatedTargets
            }
            let nonMainTargets = targetsDictionary.filter { (key: String, _) -> Bool in
                return key != mainTarget
            }
            var subSections = [IDEActivityLogSection]()
            if let mainTarget = targetsDictionary[mainTarget] {
                subSections.append(contentsOf: mainTarget.subSections)
            }
            subSections.append(contentsOf: nonMainTargets.values)
            let withTargets = self
            withTargets.subSections = subSections.sorted { lhs, rhs -> Bool in
                lhs.timeStartedRecording < rhs.timeStartedRecording
            }
            return withTargets
        } else {
            return self
        }
    }

    /// Parses the swift files compiled in a module when `whole module` is used
    ///
    /// - Parameter buildStep: the `BuildStep` that has the information about the module
    /// - Returns: An array of `BuildStep` with the data of each individual Swift file
    /// including the warnings and errors generated by its compilation.
    public func getSwiftIndividualSteps(buildStep: BuildStep) -> [BuildStep]? {
        let pattern = #"^CompileSwift\s\w+\s\w+\s.+\.swift\s"#
        guard commandDetailDesc.range(of: pattern, options: .regularExpression) == nil else {
            return nil
        }

        let swiftFilePattern = #"\s([^\s]+\.swift)"#
        guard let regexp = NSRegularExpression.fromPattern(swiftFilePattern) else {
            return nil
        }
        return regexp.matches(in: commandDetailDesc,
                              options: .reportProgress,
                              range: NSRange(location: 0, length: commandDetailDesc.count))
            .map { match -> BuildStep in
                let file = commandDetailDesc.substring(match.range(at: 1))
                return buildStep
                    .with(documentURL: "file://\(file)")
                    .with(title: "Compile \(file)")
                    .with(signature: "\(buildStep.signature) \(file)")
                    .withFilteredNotices()
        }
    }

    private func getOrBuildTarget(_ name: String,
                                  in targets: [String: IDEActivityLogSection],
                                  using section: IDEActivityLogSection)
        -> IDEActivityLogSection {
            if let target = targets[name] {
                target.timeStoppedRecording = section.timeStoppedRecording
                return target
            }
            return buildTargetSection(name, with: section)
    }

    private func buildTargetSection(_ name: String, with section: IDEActivityLogSection) -> IDEActivityLogSection {
        return IDEActivityLogSection(sectionType: 2,
                                     domainType: section.domainType,
                                     title: "Target \(name)",
            signature: "",
            timeStartedRecording: section.timeStartedRecording,
            timeStoppedRecording: section.timeStoppedRecording,
            subSections: [IDEActivityLogSection](),
            text: "",
            messages: [IDEActivityLogMessage](),
            wasCancelled: section.wasCancelled,
            isQuiet: section.isQuiet,
            wasFetchedFromCache: section.wasFetchedFromCache,
            subtitle: "",
            location: DVTDocumentLocation(documentURLString: "", timestamp: 0.0),
            commandDetailDesc: "",
            uniqueIdentifier: "",
            localizedResultString: "",
            xcbuildSignature: "",
            unknown: 0)
    }
}
