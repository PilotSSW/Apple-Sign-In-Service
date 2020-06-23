# Apple-Sign-In-Service

## Purpose
This file is meant to be a convenient way to abstract the Apple Sign-in Service and call it similarly to Facebook and Google's O-Auth services.

## How to use 
This class should be used similarly to the following: 

`
@available(iOS 13, *)
@objc func loginWithApple() {
    AppleSignInService.shared.signinRequest() { [weak self] signInResponse in
        guard let self = self else { return }

        switch signInResponse.result {
        case .failedApple(let message):
           // Alert user 

        case .userCancelled:
            break

        case .completeLoggedInWithApple:
            // Call your own Authentication service or give the user the logged app flows 

        case .completeSignedInWithApple:
            // Call your own Authentication service or give the user the logged app flows 
        }
    }
}
`
