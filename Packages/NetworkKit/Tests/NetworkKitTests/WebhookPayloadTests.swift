import XCTest
@testable import NetworkKit

final class WebhookPayloadTests: XCTestCase {
    private let schema = WebhookCatalog.ping
    private var values: [String: WebhookValue] {
        WebhookCatalog.pingValues(
            PingStatistics(host: "1.1.1.1", resolvedIP: "1.1.1.1", transmitted: 3, received: 3,
                           rttSamples: [10, 12, 11]),
            samples: [
                PingReply(sequence: 0, bytes: 64, ttl: 55, rttMillis: 10, sourceIP: "1.1.1.1"),
                PingReply(sequence: 1, bytes: 64, ttl: 55, rttMillis: 12, sourceIP: "1.1.1.1")
            ]
        )
    }

    // MARK: - Defaults

    func testDefaultsIncludeEverything() throws {
        let (body, ct) = WebhookPayloadBuilder.build(
            schema: schema, values: values, selected: schema.defaultPaths, format: .jsonNested
        )
        XCTAssertEqual(ct, "application/json")
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]

        // Types must be correct: numbers are numbers, not strings.
        XCTAssertEqual(json["host"] as? String, "1.1.1.1")
        XCTAssertEqual(json["avgMillis"] as? Double, 11)
        XCTAssertEqual(json["transmitted"] as? Int, 3)
        let samples = json["samples"] as! [[String: Any]]
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0]["rttMillis"] as? Double, 10)
        XCTAssertEqual(samples[0]["sequence"] as? Int, 0)
    }

    // MARK: - Field selection

    func testDroppingATopLevelField() throws {
        var selected = schema.defaultPaths
        selected.remove("jitterMillis")
        selected.remove("stddevMillis")
        let (body, _) = WebhookPayloadBuilder.build(schema: schema, values: values, selected: selected, format: .jsonNested)
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertNil(json["jitterMillis"], "deselected field must not be sent")
        XCTAssertNil(json["stddevMillis"])
        XCTAssertNotNil(json["avgMillis"], "kept field must still be sent")
    }

    /// The user's example: send every intermediate sample, but drop a sub-field.
    func testDroppingASampleSubField() throws {
        var selected = schema.defaultPaths
        selected.remove("samples.ttl")
        let (body, _) = WebhookPayloadBuilder.build(schema: schema, values: values, selected: selected, format: .jsonNested)
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let samples = json["samples"] as! [[String: Any]]
        XCTAssertNil(samples[0]["ttl"], "dropped sub-field must be gone from every sample")
        XCTAssertNotNil(samples[0]["rttMillis"], "kept sub-field remains")
    }

    /// The other example: keep the summary, drop the whole intermediate list.
    func testDroppingTheWholeList() throws {
        var selected = schema.defaultPaths
        selected.remove("samples")
        let (body, _) = WebhookPayloadBuilder.build(schema: schema, values: values, selected: selected, format: .jsonNested)
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertNil(json["samples"], "the whole list must be gone")
        XCTAssertNotNil(json["avgMillis"])
    }

    // MARK: - Formats

    func testFlatJSONFlattensSamples() throws {
        let (body, _) = WebhookPayloadBuilder.build(schema: schema, values: values, selected: schema.defaultPaths, format: .jsonFlat)
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertNil(json["samples"], "flat format must not keep a nested array")
        XCTAssertEqual(json["samples.0.rttMillis"] as? Double, 10)
        XCTAssertEqual(json["samples.1.sequence"] as? Int, 1)
        XCTAssertEqual(json["host"] as? String, "1.1.1.1")
    }

    func testFormURLEncoded() {
        let (body, ct) = WebhookPayloadBuilder.build(schema: schema, values: values, selected: schema.defaultPaths, format: .formURLEncoded)
        XCTAssertEqual(ct, "application/x-www-form-urlencoded")
        let s = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(s.contains("host=1.1.1.1"))
        XCTAssertTrue(s.contains("avgMillis=11"))
        XCTAssertTrue(s.contains("samples%5B0%5D%5BrttMillis%5D=10") || s.contains("samples[0][rttMillis]=10"),
                      "list elements should be indexed; got: \(s)")
    }

    // MARK: - Envelope + stability

    func testEnvelopeIncludedAndBytesStable() {
        let envelope: [String: WebhookValue] = ["event": .string("check.ping"), "version": .int(1)]
        let (b1, _) = WebhookPayloadBuilder.build(schema: schema, values: values, selected: schema.defaultPaths, envelope: envelope, format: .jsonNested)
        let (b2, _) = WebhookPayloadBuilder.build(schema: schema, values: values, selected: schema.defaultPaths, envelope: envelope, format: .jsonNested)
        XCTAssertEqual(b1, b2, "identical inputs must produce byte-identical output (so the signature is stable)")
        let json = try! JSONSerialization.jsonObject(with: b1) as! [String: Any]
        XCTAssertEqual(json["event"] as? String, "check.ping")
        XCTAssertEqual(json["version"] as? Int, 1)
    }

    // MARK: - Catalogue integrity

    func testCatalogueSchemasAreConsistent() {
        for schema in WebhookCatalog.schemas {
            XCTAssertFalse(schema.fields.isEmpty, "\(schema.toolKey) has no fields")
            let keys = schema.fields.map(\.key)
            XCTAssertEqual(Set(keys).count, keys.count, "\(schema.toolKey) has duplicate field keys")
            XCTAssertFalse(schema.defaultPaths.isEmpty)
            // Default-on paths must be a subset of all paths.
            XCTAssertTrue(schema.defaultPaths.isSubset(of: Set(schema.allPaths)))
        }
    }
}
