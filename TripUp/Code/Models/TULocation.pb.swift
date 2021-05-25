// DO NOT EDIT.
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: TULocation.proto
//
// For information on using the generated types, please see the documenation:
//   https://github.com/apple/swift-protobuf/

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that your are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

struct TULocation {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var latitude: Double = 0

  var longitude: Double = 0

  var altitude: Double = 0

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension TULocation: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "TULocation"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "latitude"),
    2: .same(proto: "longitude"),
    3: .same(proto: "altitude"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularDoubleField(value: &self.latitude)
      case 2: try decoder.decodeSingularDoubleField(value: &self.longitude)
      case 3: try decoder.decodeSingularDoubleField(value: &self.altitude)
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.latitude != 0 {
      try visitor.visitSingularDoubleField(value: self.latitude, fieldNumber: 1)
    }
    if self.longitude != 0 {
      try visitor.visitSingularDoubleField(value: self.longitude, fieldNumber: 2)
    }
    if self.altitude != 0 {
      try visitor.visitSingularDoubleField(value: self.altitude, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: TULocation, rhs: TULocation) -> Bool {
    if lhs.latitude != rhs.latitude {return false}
    if lhs.longitude != rhs.longitude {return false}
    if lhs.altitude != rhs.altitude {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}