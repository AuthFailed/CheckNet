import XCTest
@testable import NetworkKit

final class HappDecryptTests: XCTestCase {
    // crypt (mode 0, RSA-1024), synthetic vector encrypted with the bundled key.
    private let crypt1Link = "happ://crypt/SXl1EgnqXXROiH9Cu6MKol187C/GnvwexpZ7v0eCjUQnMhMsA+DwHuBaq8nzeGhcw+dokqDuf2tmV9nipnd4Dw+qozpOY7zCgqW93WBSHe1hA37lYEN6b6qc6mxjk7VVFWYNgF6Ay6bClzxtZ7lAME+tSnxL15WPpmxQm5ywBa4="
    private let crypt1Plain = "https://example.com/sub?token=abc123"

    // crypt4 (mode 3, RSA-4096), synthetic 2-block vector — exercises block concat.
    private let crypt4Link = "happ://crypt4/O39UU/X/8r04DVSJkzKuOBgLIRw0w9H0nAI78jIbcLrhPqIDKlHzM41uqmiYgmUCpwWZhWn/4n1OZ4oogymjjx1xQFwS6f/c3rAPQjXEr1p0DbAmBMyr1ThKveIcDWSAVMh8S5nuLdzOFHKv5ppIOOs8BldoI+H+q45vmksBGzOvy6XugFh/dc2Ckd6hrK2FAPRn6UigJbELPaOXlrtqeXrlFnFOl0OZxinfaBMVCNGH8CMyZFA/wqYP8Ydw7PDj/Sp07OxxGS2+BijRmBj36CVL5RkFbI08fVtInHeyKvC+3u7gb8rdhDj+KUzrDQ+lL/kqZRuKXI3t4FKQ1TOx+PrB1xY2s4QdfPI9lOp/JoJDncd25XbPJBpac/dBwacbuE7nHLbl2d5Rnlv1eCHCzBt2Opll9CWoJf9ySZ7XWhd1VN88TL5n85Pl/nJQ4uIgeTpoaWX9rd4sW1tqeTA4EduoSERu5J1igroX5TuzPKcJl2OXCUNApVWV88aWLRwouCbAU0tWqzMOnmyi5bWiub7kGSusBCCHf7onaZta0xWPkQZQNHIt9v5P4MaWcgBREPCa3DqisRkCZYagXd7WMhREBr6nlgmLOmLCEKjnlMmd+JGRnmcIYPuF9ibp6HumqqL9plPNJkutOSf1rG+JFiNeuw5TE21y9OJJl1AlVrRdD8figDS8BVG+7MUuBsO5+/d2Rz9/YAC70ogqoKNKLABPR3QyAW4ukf8nXxXciPwh8dvSXuJIp/iOmMrhzphPhurgqp9jcDA9nG1z8Fv8yHv71VdUdWFqi4cHPhawEDMFnAFK+0LHROEmqZl//NqAy5hAAgZeEH0qZA5tR2lEx7dxquQgzHRelRjhIXVGrGaRMFkx8IAsKOUCi/C6Sks6C99pNsPdQUFYyi0Ngd7OceyYUX0NaaOdwLeUk58lxG8JbPe0MgVtisiuhH8ZmZcqZcMuPXHAaGjPv3RPKXVdW+6RHLEViLRgnXEEfDWken3Pno16lUJu+0hqYMbRsNFP4xw8w/MRoAntjrMW0D00Or+JyOn1IpqlVKUsLCFqeebRc5KUrtW7cvsk8t9Lza300h0k2mqXy03wPC0QRetpY1xIpaWDAHWjVTEIy9BOi+JnLpo1vsygZ5VrI7i6tk6zwtZS8UM4rdcEkt1hlJBrz59hW1CJ1hak+mQPZN2wm3X4FxHXU4Glw5iYnWBcJCbjP6izYh0BuJyOppdDNWoXO6w7co7C8G6yaH21JWUShpNygTqtV8qDtLVQhOajdacmueXISMqK/kCgc9Mgxrns2xzzLY4QD0D6AWe1Ev+pyyhXeHeKv2iuqUeiT/cY4UXxPtI5kCiHw9YzeF6ONr8Y3g=="
    private var crypt4Plain: String { "https://example.com/sub?token=" + String(repeating: "a", count: 580) }

    // crypt5 (RSA + ChaCha20-Poly1305) — real vector from the reference decryptor.
    private let crypt5Link = "happ://crypt5/fzvdO4bMOfTWNaB3taWRhRaF64soexaE9dm3ZlLK0Rke9Rz3BG1f9gmj4tSDpjRSWWdX5G6oaaQK9Gs+fdJPWNXIF08BsaeifWtfTlCvC/nSWDv0ZrofgJXkQ8MlUk63CoJkt7RvXAfablYXb/cYWEZJQkDMyMaE5/1KegAbWVWVI60MPqDylUyYoLtOeOOX9amvELecOZ4kKz1QVqgE9uCBz3py+3Ghr1iVGKOhFwb98OFP+j0tGvDo/3d609DVq3RwBGXu1ogZ7PTc3/A5IlaA3Hff5IlVujozQ3ywmQBsTGd+l3AHJAX1oDbPkRSSwg7Y7hl3AKXKpZsEhMzPbJY8UxZ7GmVsxeROLopVx85ACqakzg+ZZwdZslfKgdRzUmL9Mv895HDOHE3tbh6qnDhE9Ew/Epx1iBCb2HjorOLDBluH8ztdL9mdUX+turjC4GLN0YR55P3H23A0W5zl0di5YfrI2nUBKxh30lUVG9NbqYKlwxgmhxAUZrQ6cnFGF2VuZ9VJLQ3sQ8rqXTtfau8ySbu770Hd6vVEun8aSJm4W4M0DagKbORL4A4M6Cuf1v/jj7EWhA9yhhcSuxkc6WUWMGYRraWBM9vSrSbjeT1U69a3n9T56M/TOJWf4z8fXrHRnCR1tfzwrjHiOJfZGiKvbAd4k6f+VADYpLdCq+ornEElv7V0sByfwPTgep+Q33Qkl67ArHpmbZDcCyWkGz0BoUzGJFe58YiS/oNFVdufbuDnFd1ArAVMztJJJbxlo4Is48+Iof=ff"
    private let crypt5Plain = "https://example.com/sub"

    func testDecryptCrypt1() throws {
        XCTAssertEqual(try HappDecrypt.decrypt(crypt1Link), crypt1Plain)
    }

    func testDecryptCrypt4MultiBlock() throws {
        XCTAssertEqual(try HappDecrypt.decrypt(crypt4Link), crypt4Plain)
    }

    func testDecryptCrypt5() throws {
        XCTAssertEqual(try HappDecrypt.decrypt(crypt5Link), crypt5Plain)
    }

    func testCrypt5RejectsTampered() {
        let payload = String(crypt5Link.dropFirst("happ://crypt5/".count))
        let idx = payload.index(payload.startIndex, offsetBy: 200)
        let tampered = "happ://crypt5/" + payload.prefix(200) + "A" + payload[payload.index(after: idx)...]
        XCTAssertThrowsError(try HappDecrypt.decrypt(tampered))
    }

    func testInspectPreviewsMode() {
        XCTAssertEqual(HappDecrypt.inspect(crypt5Link)?.name, "crypt5")
        XCTAssertEqual(HappDecrypt.inspect(crypt1Link)?.mode, 0)
        XCTAssertNil(HappDecrypt.inspect("https://example.com"))
    }

    func testRejectsNonCryptLink() {
        XCTAssertThrowsError(try HappDecrypt.decrypt("happ://routing/add/abc")) { error in
            XCTAssertEqual(error as? HappDecrypt.DecryptError, .notACryptLink)
        }
    }

    func testByteTransformsAreSelfInverse() {
        let sample: [UInt8] = Array("ABCDEFGH".utf8)
        XCTAssertEqual(HappDecrypt.swapBlockHalves(HappDecrypt.swapBlockHalves(sample)), sample)
        XCTAssertEqual(HappDecrypt.swapAdjacent(HappDecrypt.swapAdjacent(sample)), sample)
    }
}
