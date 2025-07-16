// Copyright (c) 2025 PassiveLogic, Inc.

import QSCIntrospectionKitDriver

import class Foundation.JSONEncoder
import class QortexREPL.REPLInterface
import enum QuantumInterface.Quantum
import struct QuantumInterface.RootedQuantumGraphEncoder

extension REPLInterface {
    /// Import QStack packages needed by QortexInferencing.
    private func importPackages() async throws {
        _ = try await self.sendCommand(.swift("import Foundation"))
        _ = try await self.sendCommand(.swift("import QuantumInterface"))
        _ = try await self.sendCommand(.swift("import IntrospectionKit"))
        _ = try await self.sendCommand(.swift("import QSCIntrospectionKitDriver"))
        _ = try await self.sendCommand(.swift("import OrderedCollections"))
        _ = try await self.sendCommand(.swift("import AnyCodableREPL"))
    }

    /// Injects a site.json file into the REPL container and loads the site in that REPL.
    /// - Parameters:
    ///   - fileName: The filename of the site to inject, does not include extension.
    ///   - site: The site which will be loaded into the REPL.
    public func saveAndLoadSiteGraph(_ site: Quantum.Site.CGraph, as fileName: String) async throws
    {
        let encoder = RootedQuantumGraphEncoder(options: [.disableStateEncoding, .compact])
        let siteData = try encoder.encode(site.rootedQuantumGraph)
        try siteData.write(to: sharedVolume.hostPath.appending(path: fileName + ".json"))

        try await self.importPackages()

        let loadDataCmd = """
            let siteData = try Data(contentsOf: URL(fileURLWithPath: "\(self.sharedVolume.containerPath.path())/\(fileName).json"))
            let slowSite = try RootedQuantumGraphDecoder(options: [.ignoreState]).decode(withRoot: Quantum.Site.self, from: siteData)
            let \(self.siteVarName) = try slowSite.withHyperGraph()
            """
        _ = try await self.sendCommand(.swift(loadDataCmd), timeout: .seconds(240))
    }

    public func loadComputedAttributes() async throws {
        _ = try await self.sendCommand(
            .swift(
                """
                public extension Quantum.Building {
                    var height: (val: Double, unit: String)? {
                        guard let roof = self.floors.first(where: { $0.name == "Roof" }) else { return nil }
                        guard let elevation = roof.properties.first(where: { $0.name == "elevation" }) else { return nil }
                        guard let unitProp = self.properties.first(where: { $0.name == "geometryUnits" }) else { return nil }

                        guard let height = elevation.currentValue, let unit = unitProp.unit else { return nil }
                        return (val: height, unit: unit.rawValue)
                    }
                }

                public extension Quantum.Surface {
                    var area: (val: Double, unit: String)? {
                        switch self.surfaceType {
                            case .Wall:
                                guard let zoneVertices = self.zone?.surfaces.first(where: { $0.surfaceType == .Boundary })?.shapes.first?.vertices else { return nil }
                                guard let definingWallVertex = self.vertices.first else { return nil } /// The vertex which defines the wall

                                /// Find the corresponding index of the vertex which shares the wall.
                                let nextIndex = (definingWallVertex.index + 1) % zoneVertices.count
                                guard let partnerWallVertex = zoneVertices.first(where: { $0.index == nextIndex }) else { return nil }
                                let wallLength = sqrt(pow(definingWallVertex.x - partnerWallVertex.x, 2) + pow(
                                    definingWallVertex.y - partnerWallVertex.y,
                                    2
                                ))

                                guard let heightProp = self.zone?.properties.first(where: { $0.name == "height" }) else { return nil }
                                guard let height = heightProp.currentValue, let unit = heightProp.unit else { return nil }

                            return (val: wallLength * height * 2, unit: "Square \\(unit.rawValue)")
                            case .Glazing:
                                let properties = self.properties.filter({ $0.name == "width" || $0.name == "height" })
                                guard let unit = properties.first?.unit else { return nil }
                                let oneSideArea = properties.reduce(1.0) { partialResult, prop in
                                    partialResult * (prop.currentValue ?? 1)
                                }
                            return (val: oneSideArea * 2, unit: "Square \\(unit.rawValue)")
                            default:
                                return nil
                        }
                    }

                    var isExterior: Bool {
                        let subSurfaces = self.parentAdjacencies.compactMap(\\.childSurface)
                        let outdoorAdjs = subSurfaces.compactMap { $0.childAdjacencies.first { $0.adjacencyType == .Outdoors } }
                        return !outdoorAdjs.isEmpty
                    }
                }

                public extension Quantum.Equipment {
                    /// Get all equipments from this `Equipment` that are connected through `ConnectionNodes`
                    /// with different connection directions
                    var connectedEquipments: [Quantum.Equipment] {
                        var equipmentComponents = self.equipmentComponents
                        if let aliasEquipmentComponent = self.aliasEquipmentComponent {
                            equipmentComponents.append(aliasEquipmentComponent)
                        }
                        var allConnectedEquipments = [Quantum.Equipment]()
                        for equipmentComponent in equipmentComponents {
                            for connectionNode in equipmentComponent.connectionNodes {
                                /// For each connectionNode with direction `Input`
                                if let connNet = connectionNode.connectionNet {
                                    /// Find connectionNodes on the same connectionNet with a different connection direction
                                    let otherConnectionNodes = connNet.connectionNodes.filter {
                                        $0.connectionDirection != connectionNode.connectionDirection &&
                                            $0.ID != connectionNode.ID &&
                                            $0.configuredQuanta?.quantaType == connectionNode.configuredQuanta?.quantaType
                                    }
                                    for otherNode in otherConnectionNodes {
                                        /// Now trace back from the other connectionNode to reach to the equipment
                                        /// and if th equipment is different than the one connected to the first connectionNode (i.e., not a loop back to
                                        /// itself), then this equipment is connected to another equipment.
                                        /// i.e., if below exists, and `candidate.isSensor` then `candidate` is an equipment sensor
                                        /// candidate --> EquipmentComponent --> InputConnectionNode --> ConnectioNet <-- OutputConnectionNode
                                        /// <--EquipmentComponent <-- Equipment
                                        let connectedEquipments: [Quantum.Equipment?] = [otherNode.equipmentComponent?.equipment] +
                                            Array(otherNode.equipmentComponent?.aliasEquipments ?? [])
                                        allConnectedEquipments.append(contentsOf: connectedEquipments.compactMap { $0 }.filter { $0.ID != self.ID })
                                    }
                                }
                            }
                        }
                        return allConnectedEquipments
                    }

                    /// Get all neighbor equipment
                    var neighborEquipment: OrderedSet<Quantum.Equipment> {
                        let connectionNodes = self.aliasEquipmentComponent?.connectionNodes ?? []
                        return connectionNodes.reduce(into: []) { result, connectionNode in
                            let otherNodes = connectionNode.connectionNet?.connectionNodes.filter {
                                guard $0 != connectionNode else {
                                    return false
                                }
                                guard $0.connectionDirection != connectionNode.connectionDirection else {
                                    return false
                                }
                                return $0.configuredQuanta?.quantaType == connectionNode.configuredQuanta?.quantaType
                            } ?? []
                            otherNodes.forEach { result.append(contentsOf: $0.equipmentComponent?.aliasEquipments ?? []) }
                        }
                    }

                    /// To filter equipment sensors
                    var isEquipmentSensor: Bool {
                        if self.isSensor && (self.containedByOtherEquipment || self.hasConnectedEquipments) {
                            return true
                        }
                        return false
                    }

                    /// True if this equipment is contained by other equipment
                    var containedByOtherEquipment: Bool {
                        !self.containingEquipments.isEmpty
                    }

                    /// to filter zone-only sensors
                    var isZoneSensor: Bool {
                        // must be a sensor
                        guard self.isSensor else {
                            return false
                        }

                        // if the equipment has adjacencies (that is, it is connected
                        // to surfaces via adjacencies) then it's automatically a zone - only
                        // sensor - that's how it's done in newer models
                        // TODO: the additionall hasInputToOutputConnectedEquipments check is added here to not consider
                        // equipment sensors that are connected to zones temporarily. Remove later
                        if self.aliasEquipmentComponent?.adjacencies.isEmpty == false && !hasConnectedEquipments {
                            return true
                        }

                        // in the older models the sensor is connected to the zones
                        // directly
                        // TODO: the additionall hasInputToOutputConnectedEquipments check is added here to not consider
                        // equipment sensors that are connected to zones temporarily. Remove later
                        guard self.zone != nil && !hasConnectedEquipments else {
                            return false
                        }

                        // also, in the older models, the sensor is not connected to other
                        // equipment so it would not be categorized as equipment sensor
                        return !self.isEquipmentSensor
                    }

                    /// Tells if this equipment is a sensor (quantum type super class is .Data)
                    var isSensor: Bool {
                        guard let aliasEquipmentComponent = self.aliasEquipmentComponent else {
                            return false
                        }
                        guard aliasEquipmentComponent.actorType == .Producer else {
                            return false
                        }
                        return aliasEquipmentComponent.characteristicQuanta?.quantaType?.quantaSuperClass == .Data
                    }

                    var hasConnectedEquipments: Bool {
                        return self.connectedEquipments.map { $0.ID }.filter({ $0 != self.ID }).count > 0
                    }
                }
                """
            ),
            timeout: .seconds(240)
        )
    }
}
