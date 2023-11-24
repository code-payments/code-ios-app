//
//  SolanaTransaction+Mock.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeServices

extension SolanaTransaction {
    
    typealias TransactionTuple = (transaction: SolanaTransaction, base64: String)
    
    /// Mock Timelock Create Account Transaction
    ///
    /// - Instruction 1: Advance Nonce (No Change)
    ///
    /// - Instruction 2: Initialize Timelock
    ///   - Accounts
    ///     - Timelock: 4B6DvoEJugGBrKedasVvT2n5GykbtsVUFknsz12FWEv9
    ///     - Vault: EQDNoJMxbAWr81XFM1TykpFuJuK5CjxmJLyP45S95wR8
    ///     - VaultOwner: G9zksyBhzGzFDPjfF333HEXCWKstU8Go4JvUChBNBLf7
    ///     - Mint: kinXdEcpDQeHPEuQnqmUgtYykqKGVFq6CeVX5iAHJq6
    ///     - Time Authority: codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR
    ///     - Payer: codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR
    ///
    /// - Instruction 3: Activate Timelock
    ///   - Arguments
    ///     - Timelock Bump: 254
    ///     - Unlock Duration: 1209600
    ///   - Accounts
    ///     - Timelock: 4B6DvoEJugGBrKedasVvT2n5GykbtsVUFknsz12FWEv9
    ///     - Time Authority: codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR
    ///     - Vault Owner: G9zksyBhzGzFDPjfF333HEXCWKstU8Go4JvUChBNBLf7
    ///     - Payer: codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR
    ///
    static func mockTimelockCreateAccount() -> TransactionTuple {
        transaction(from: "AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAHCwksDha4qmHvDLlGQXd2cjb/PDR7UoWkLijNmnwnO1nuN8DXVqgdQXIsX+LDS9MUe8jvjg/Ff6Vj6VZaNxer98K8yIAO97UcHAd2xm4zfG8AtfQDMyT8/7QC0Sen9vq/lgSaWxmcYQR245MI8/QpznC4B3qZptwxn5SBWI9Bizr8PKg85sywGzAYembl67Ega1GZSC7hiY7u3Yz/akHwTAoGp9UXGSxWjuCKhF9z0peIzwNcMUWyGrNE2AYuqUAAAAan1RcZLFxRIYzJTD1K8X9Y2u4Im6H9ROPb2YoAAAAACzM4oKssyEHVsBS8ajz3VikYdLMZyVF9m7+p5OlmHvkG3fbh12Whk9nL4UbO63msHLSF7V9bN5E6jPWFfv8AqQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADT/Zr02LPzD6xb5Nf2x4+R0n7wWJyKAfah6AyAlWXFeo9TwTAtFbaDGnTWWclU2+wNsZXm1C/+ztSBss80USmAIKAwEFAAQEAAAACgoJAgMEBwAACAkGEK+vbR8NmJvtgK8bAAAAAAA=")
    }
    
    /// Mock Timelock Transfer Transaction
    ///
    /// - Instruction 1: Advance Nonce (No Change)
    ///
    /// - Instruction 2: Memo (No Change)
    ///
    /// - Instruction 3: Transfer With Authority
    ///   - Arguments
    ///     - Timelock Bump: 254
    ///     - Amount: 100,000
    ///   - Accounts
    ///     - Timelock: 4B6DvoEJugGBrKedasVvT2n5GykbtsVUFknsz12FWEv9
    ///     - Vault: EQDNoJMxbAWr81XFM1TykpFuJuK5CjxmJLyP45S95wR8
    ///     - Vault Owner: G9zksyBhzGzFDPjfF333HEXCWKstU8Go4JvUChBNBLf7
    ///     - Time Authority: codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR
    ///     - Destination: 67ziVAtk8djEKbwNtFhUPrkiEi8RdYaq4GXkpHzHd2Nq
    ///     - Payer: codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR
    ///
    static func mockTimelockTransfer() -> TransactionTuple {
        transaction(from: "AqWNqWCdgbzlWTVZQB7+iBg52O9A8107s/pfQ/Z2FndWizwNXukZioklvScCgQTZFr2f3eg4ojfEvpiZqwm9+wAiQGg5UsZEf/DjuHrnZr7YxHl0dIZexmPtmpgOdI69G7YVGSk2rE3sLk+65GeFUoDhpq7tzxP9W6nWzI5/5HQHAgEGCwksDha4qmHvDLlGQXd2cjb/PDR7UoWkLijNmnwnO1nuu7Xnafr2nnC0//MZTieqGWg8ygCot6SYJVjyndZCxGoaDXxcmpoifit1bsGjzYQ/vWUcn2k/tEUOjKQmrm5eKRu4eednzoBrNKpxRazVlEwA0hfWw9AnV3fGaPVtKli874Pwj2BfKXqwWqg0L7RsCDBgdqH2i6hMyNuRTnhIR1sGp9UXGSxWjuCKhF9z0peIzwNcMUWyGrNE2AYuqUAAAAbd9uHXZaGT2cvhRs7reawctIXtX1s3kTqM9YV+/wCp58J2lG1wb0LqCFPN9+Fla+HyGz75GCqQaZxuRH8yyfEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVKU1D4XciC1hSlVnJ4iilt3x6rq9CmBniISTL07vagDT/Zr02LPzD6xb5Nf2x4+R0n7wWJyKAfah6AyAlWXFf4ixn10XVBBNgH+xMmt/5cXJ6W7m1U9liIi4o8EvBHfAMIAwQFAAQEAAAACQAsWlRBRUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQT0KCAcCAQADAAYIEUSA3sCBRUel/0ANAwAAAAAA")
    }
    
    /// Mock SPL Transfer Transaction
    ///
    /// - Instruction 1: Advance Nonce
    ///
    /// - Instruction 2: Memo
    ///
    /// - Instruction 3: Token Transfer
    ///   - Arguments:
    ///     - Amount: 100,000
    ///   - Accounts:
    ///     - Source: HFMeSarShcvgKARwwMTS6WafuRzhW1BPRsWzo3WEa4FS
    ///     - Destination: FmoyfcoDYya27XtJcZUKtnXRn6RKNA8yrApkf88DcKvj
    ///
    static func mockSimpleTransfer() -> TransactionTuple {
        transaction(from: "A1tAcqFQvsLAwkzzR6IyioVR7RanubupIBmSTJLmVRgehHpCXA4vw1iydd/nXGRM2MFkcOO486sPbY/t5YkcoQ+HczaWQofwtUOGMXOaitdnW4QV2IrNouP7OekZ5X/nrVTaMNsRldU4hDKv4TpBW5ZtUuMxNj+K0hYaiOhe0bwAe03tCXMy5w2tn22FQRD98vyOk9lllvhOiNvrz2MkQBrKyGZkvFx+GxzIr2JjKp2ZcLiYQAabpKmmqae3WbejDAMBBAkJLA4WuKph7wy5RkF3dnI2/zw0e1KFpC4ozZp8JztZ7gu8C2nMEidsVQv64veR8KGN+uSVB8t3QXls8pS1g3hpYe7aeLzQPu4s5+1/zFV3d0sA+QjBW17I1Gz2kSOyqk7bfkolDNcGZ49pe8RELDOdW6UGljTmveo3XvKO0SSYDPFod1RaA9JNk/lmcAnsZEkxtqcuUgnkYIlTqbFPislJBqfVFxksVo7gioRfc9KXiM8DXDFFshqzRNgGLqlAAAAFSlNQ+F3IgtYUpVZyeIopbd8eq6vQpgZ4iEky9O72oAbd9uHXZaGT2cvhRs7reawctIXtX1s3kTqM9YV+/wCpAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB9c5VBOZKF0Rkn4tPQFamDoUjF8oa04karh4ZnmDORpgMIAwEFAAQEAAAABgAsWlRBRUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQT0HAwQDAgkDoIYBAAAAAAA=")
    }
    
    // MARK: - Actions -
    
    static func mockCloseDormantAccount() -> TransactionTuple {
        transaction(from: "Ag83S4kpkDdVCkjHoQMbY1PFlHQuN4iNc0HvKRY4GAYtS2fJg2sD0pTswcXX80wQ0l1LNzfEPMFq1L65zh3ZqAMalMR4K8eVSOb2026zqdo2y+jtsqXZUwLXo5u7kpxcQdesl0RyvYFW5TtfOahNZEmt130Bqr7JW52XByUWOMUFAgEFCwksDha4qmHvDLlGQXd2cjb/PDR7UoWkLijNmnwnO1nuymNnIuP7iSQN87RAiXXExCM/rcMSDk1ufucz1QBgrMsQi2SY08yHh0QVR56YXP/W3hU8rVeYaNQ3Pou62KeUaMXihwH1Rl/jONnj6X35HTZ5IaCcgRGCf5ejrg2iOClK2CjKDyXQ3p6u/9OZeYr/MDJt3dfzYPPo50L/Nl89J5fiWbl2YMre3ew8o0M5ZWp069OdcB1BTXvdFHPVb8kEggan1RcZLFaO4IqEX3PSl4jPA1wxRbIas0TYBi6pQAAABt324ddloZPZy+FGzut5rBy0he1fWzeROoz1hX7/AKkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVKU1D4XciC1hSlVnJ4iilt3x6rq9CmBniISTL07vagDT/Zr02LPzD6xb5Nf2x4+R0n7wWJyKAfah6AyAlWXFdklqEX6a61ZsH0qvimrsORM6Wqr1q/dAdLEVNifIlQSgYIAwIGAAQEAAAACQAsWlRBRUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQT0KBgQDAAAHCAnltTryqwjJkP8KAwQBAAkscCGscRyODf8KBwQDAQUABwgJtxJGnJRtoSL/CgYEAwAABwgJq95e6SL6ygH/")
    }
    
    static func mockPrivateTransfer() -> TransactionTuple {
        transaction(from: "AqWNqWCdgbzlWTVZQB7+iBg52O9A8107s/pfQ/Z2FndWizwNXukZioklvScCgQTZFr2f3eg4ojfEvpiZqwm9+wAiQGg5UsZEf/DjuHrnZr7YxHl0dIZexmPtmpgOdI69G7YVGSk2rE3sLk+65GeFUoDhpq7tzxP9W6nWzI5/5HQHAgEGCwksDha4qmHvDLlGQXd2cjb/PDR7UoWkLijNmnwnO1nuu7Xnafr2nnC0//MZTieqGWg8ygCot6SYJVjyndZCxGoaDXxcmpoifit1bsGjzYQ/vWUcn2k/tEUOjKQmrm5eKRu4eednzoBrNKpxRazVlEwA0hfWw9AnV3fGaPVtKli874Pwj2BfKXqwWqg0L7RsCDBgdqH2i6hMyNuRTnhIR1sGp9UXGSxWjuCKhF9z0peIzwNcMUWyGrNE2AYuqUAAAAbd9uHXZaGT2cvhRs7reawctIXtX1s3kTqM9YV+/wCp58J2lG1wb0LqCFPN9+Fla+HyGz75GCqQaZxuRH8yyfEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVKU1D4XciC1hSlVnJ4iilt3x6rq9CmBniISTL07vagDT/Zr02LPzD6xb5Nf2x4+R0n7wWJyKAfah6AyAlWXFf4ixn10XVBBNgH+xMmt/5cXJ6W7m1U9liIi4o8EvBHfAMIAwQFAAQEAAAACQAsWlRBRUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQT0KCAcCAQADAAYIEUSA3sCBRUel/0ANAwAAAAAA")
    }
    
    static func mockCloseEmptyAccount() -> TransactionTuple {
        transaction(from: "AliNx0Qd/Yh3rxDOm7tP6Nk5F/kIqkBCgUxtiPXbPa4hI/lPvnFu2R1kOUPSVyXfukFkhWVmVMbAhPsC1julZQZgPnBJozuXsURdMLy8FyhML7D4H0v1fhCHQJMOoAORJO75IeFbekkBWFFZZK+TOhBApSCQK4uEdjv7lyhK7dEDAgEECgksDha4qmHvDLlGQXd2cjb/PDR7UoWkLijNmnwnO1nuAwAkc+jnVXSj6mVi3qDSxmtMOwdDpQZWwcrlIreF0/0B6uU3GHXrot2xFmpofLZ+RJ3k0x3D0yyzG7HtV5blAgszOKCrLMhB1bAUvGo891YpGHSzGclRfZu/qeTpZh75/IUvnzG1DltbSH1irqx2Cyh7SroxvAgiqc8rXoqDGHz/5wv1HyDU2Q6Ue0j8NoyFFNuy3gehalCj+lmXjCqUuQan1RcZLFaO4IqEX3PSl4jPA1wxRbIas0TYBi6pQAAABt324ddloZPZy+FGzut5rBy0he1fWzeROoz1hX7/AKkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA0/2a9Niz8w+sW+TX9sePkdJ+8FicigH2oegMgJVlxXnFoL9tCTU/3A8XPsFV4gd1BbGTdFQhiF05WPGERPmJIDCAMFBgAEBAAAAAkIBAIBAAMABwgRJyr/2g58Ti3/oIYBAAAAAAAJBgQCAAAHCAmr3l7pIvrKAf8=")
    }
    
    // MARK: - Utilities -
    
    private static func transaction(from base64: String) -> TransactionTuple {
        (SolanaTransaction(data: Data(base64Encoded: base64)!)!, base64)
    }
}
