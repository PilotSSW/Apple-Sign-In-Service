//
//  AppleSignInService.swift
//  SSW 
//
//  Created by Sean Wolford on 4/30/20.
//  Copyright © 2020 SSW. All rights reserved.
//

import Foundation
import AuthenticationServices

@available(iOS 13.0, *)
class AppleSignInService: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = AppleSignInService()

    enum AppleSignInResult {
        case completeLoggedInWithApple
        case completeSignedInWithApple
        case failedApple(message: String = "")
        case userCancelled
    }

    struct AppleSignInResponse {
        let result: AppleSignInResult
        let identityToken: String?
        let appleUserID: String?
        let email: String?
        let fullName: PersonNameComponents?
    }

    var appleSigninCallback: ((AppleSignInResponse) -> Void)? = nil

    private override init() {
        super.init()
    }

    internal func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let window = UIViewController.top()?.view.window else {
            assertionFailure("No window for apple sign in to adhere to")
            return UIApplication.shared.keyWindow!
        }
        return window
    }

    func signinRequest(completion: @escaping ((AppleSignInResponse) -> Void)) {
        appleSigninCallback = completion

        let appleIDProvider = ASAuthorizationAppleIDProvider()

        let providerRequest = appleIDProvider.createRequest()
        providerRequest.requestedScopes = [.email, .fullName]

        let signInController = ASAuthorizationController(authorizationRequests: [providerRequest])

        signInController.delegate = self
        signInController.presentationContextProvider = self

        signInController.performRequests()
    }

    /// - Tag: did_complete_authorization
    internal func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        switch authorization.credential {
        case let appleIDCredential as ASAuthorizationAppleIDCredential:
            if let data = appleIDCredential.identityToken {
                let identityToken = String(decoding: data, as: UTF8.self)

                let signedInWithApple = appleIDCredential.email != nil

                if signedInWithApple {
                    if let applePersonObject = appleIDCredential.fullName {
                        AppleUserStore.storeAppleUser(withAppleUserId: appleIDCredential.user,
                                                      appleUserObject: applePersonObject)
                    }
                    if let appleEmail = appleIDCredential.email {
                        AppleUserStore.storeAppleEmail(forAppleUserId: appleIDCredential.user,
                                                       email: appleEmail)
                    }

                    let appleSignInResponse = AppleSignInResponse(result: .completeSignedInWithApple,
                                                                  identityToken: identityToken,
                                                                  appleUserID: appleIDCredential.user,
                                                                  email: appleIDCredential.email,
                                                                  fullName: appleIDCredential.fullName)
                    appleSigninCallback?(appleSignInResponse)
                    appleSigninCallback = nil

                // Case: Apple has already stored the credentials and is treating this case as a login, we need to fetch them
                // from disk and return them.
                } else {
                    let applePersonObject: PersonNameComponents? = AppleUserStore.getAppleUser(withAppleUserId: appleIDCredential.user)
                    let appleEmail: String? = AppleUserStore.getAppleEmail(forAppleUserId: appleIDCredential.user)

                    let appleSignInResponse = AppleSignInResponse(result: .completeLoggedInWithApple,
                                                                  identityToken: identityToken,
                                                                  appleUserID: appleIDCredential.user,
                                                                  email: appleEmail,
                                                                  fullName: applePersonObject)
                    appleSigninCallback?(appleSignInResponse)
                    appleSigninCallback = nil
                }
            }
            else {
                appleSigninCallback?(AppleSignInResponse(result: .failedApple(message: "Failed to parse identity token."),
                                                         identityToken: nil,
                                                         appleUserID: nil,
                                                         email: nil,
                                                         fullName: nil))
                appleSigninCallback = nil
            }

        // Case: User was able to sign-up password - we shouldn't see this case.
        case _ as ASPasswordCredential:
            appleSigninCallback?(AppleSignInResponse(result: .failedApple(message: "Apple returned password credential"),
                                                     identityToken: nil,
                                                     appleUserID: nil,
                                                     email: nil,
                                                     fullName: nil))
            appleSigninCallback = nil
            assertionFailure("Apple Sign-in returned password credential.")

        default:
            break
        }
    }

    /// - Tag: did_not_complete_authorization
    internal func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {

        // Case: User cancelled login / sign-up flow.
        if (error as NSError).code == 1000 || (error as NSError).code == 1001 {
            appleSigninCallback?(AppleSignInResponse(result: .userCancelled,
                                                     identityToken: nil,
                                                     appleUserID: nil,
                                                     email: nil,
                                                     fullName: nil))
        } else {
            appleSigninCallback?(AppleSignInResponse(result: .failedApple(message: error.localizedDescription),
                                                     identityToken: nil,
                                                     appleUserID: nil,
                                                     email: nil,
                                                     fullName: nil))
        }

        appleSigninCallback = nil
    }
}

class AppleUserStore {
    ///
    /// This function is used to store an Apple PersonNameComponents object when they use Apple Sign-In to authenticate
    /// with this app. This will be needed if they Apple has validated their account, but for some reason sign-up with
    /// our SDService using the social auth has failed. This user object is only returned once from apple and will need
    /// to be fetched from this function to retry with SDService.
    ///
    /// - Parameters:
    ///   - userId: The user's 'Apple user id' returned from the Apple Sign Service
    ///   - appleUserObject: The PersonNameComponents object with the user's first and last name
    static func storeAppleUser(withAppleUserId userId: String, appleUserObject: PersonNameComponents) {
        let key = userId + "_applePersonObject"
        do {
            let personData = try NSKeyedArchiver.archivedData(withRootObject: appleUserObject, requiringSecureCoding: true)
            UserDefaults.standard.set(personData, forKey: key)
        } catch(let error) {
            let personData = NSKeyedArchiver.archivedData(withRootObject: appleUserObject)
            UserDefaults.standard.set(personData, forKey: key)
        }
    }

    ///
    /// This function should be used to retrieve a user's associated Apple PersonNameComponents object (containing their
    /// first and last name) in case it is ever needed in the future.
    /// - Parameter userId: The user's 'Apple user id' returned from the Apple Sign Service
    /// - Returns: The PersonNameComponents object with the user's first and last name
    static func getAppleUser(withAppleUserId userId: String) -> PersonNameComponents? {
        let key = userId + "_applePersonObject"
        if let personData = UserDefaults.standard.data(forKey: key) {
            if let appleUserObject = NSKeyedUnarchiver.unarchiveObject(with: personData) as? PersonNameComponents {
                return appleUserObject
            }
        }

        return nil
    }

    static func storeAppleEmail(forAppleUserId userId: String, email: String) {
        let key = userId + "_emailAddress"
        UserDefaults.standard.set(email, forKey: key)
    }

    static func getAppleEmail(forAppleUserId userId: String) -> String? {
        let key = userId + "_emailAddress"
        return UserDefaults.standard.string(forKey: key)
    }
}
