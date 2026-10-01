import Foundation
import CryptoKit
let args=CommandLine.arguments
if args.count != 4 {fputs("Usage: verify_update_archive archive public-key signature\n",stderr);exit(2)}
do {
    guard let keyData=Data(base64Encoded:args[2]),let signature=Data(base64Encoded:args[3]) else{throw NSError(domain:"Signature",code:1)}
    let key=try Curve25519.Signing.PublicKey(rawRepresentation:keyData)
    guard key.isValidSignature(signature,for:try Data(contentsOf:URL(fileURLWithPath:args[1]))) else{throw NSError(domain:"Signature",code:2)}
    print("PASS: update archive verifies against the application's public key")
}catch{fputs("Update signature verification failed\n",stderr);exit(1)}
