//
//  OnboardingViewController.swift
//  breadwallet
//
//  Created by Ray Vander Veen on 2018-10-30.
//  Copyright © 2018-2019 Breadwinner AG. All rights reserved.
//

import UIKit
import AVKit

enum OnboardingExitAction {
    case restoreWallet
    case createWallet
    case restoreCloudBackup
}

typealias DidExitOnboardingWithAction = ((OnboardingExitAction) -> Void)

struct OnboardingPage {
    var heading: String
    var subheading: String
    var videoClip: String
}

// swiftlint:disable type_body_length

/**
*  Takes the user through a sequence of onboarding screens (product walkthrough)
*  and allows the user to either create a new wallet or restore an existing wallet.
*
*  As the user taps the Next button and transitions through the screens, video clips
*  are played in the background.
*/
class OnboardingViewController: UIViewController {
    
    // This callback is passed in by the StartFlowPresenter so that actions within 
    // the onboarding screen can be directed to other functions of the app, such as wallet
    // restoration, PIN creation, etc.
    private var didExitWithAction: DidExitOnboardingWithAction?
        
    private let logoImageView: UIImageView = UIImageView(image: UIImage(named: "LogoGradientLarge"))
    
    private var showingLogo: Bool = false {
        didSet {
            let alpha: CGFloat = showingLogo ? 1 : 0
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: { 
                self.logoImageView.alpha = alpha
            }, completion: nil)
        }
    }
    
    // Cache a separate player and video layer for each page that shows a video
    // clip so that all we have to do is unhide the layer and play the clip. If
    // we use a single player and make calls to replaceCurrentItem() it tends to
    // cause a slight judder when starting the next clip.
    var videoPlayers: [AVPlayer] = [AVPlayer]()
    var videoLayers: [AVPlayerLayer] = [AVPlayerLayer]()
    
    var videoRates: [Float] = [1.2, 1.2, 1.2]
    
    // Each video clip is embedded as an AVPlayerLayer within a container view.
    // Visibility of the container views is controlled by setting their alpha
    // values to 0 or 1 in prepareVideoPlayer()
    private var videoContainerViews: [UIView] = [UIView]()

    // page content
    var pages: [OnboardingPage] = [OnboardingPage]()
    
    // delays for starting page animations; fourth page is tuned so as not to overlay
    // with the video content
    var animationDelays: [TimeInterval] = [0, 0.2, 0.2, 0.4]
    
    // controls how far the heading/subheading labels animate up from the constraint anchor
    var fadeInOffsetFactors: [CGFloat] = [2.0, 2.0, 3.0, 2.0]
    
    let firstTransitionDelay: TimeInterval = 1.2
    
    // Heading and subheading labels and the constraints used to animate them.
    var headingLabels: [UILabel] = [UILabel]()
    var subheadingLabels: [UILabel] = [UILabel]()    
    var headingConstraints: [NSLayoutConstraint] = [NSLayoutConstraint]()
    var subheadingConstraints: [NSLayoutConstraint] = [NSLayoutConstraint]()
    
    let headingLabelAnimationOffset: CGFloat = 60
    let subheadingLabelAnimationOffset: CGFloat = 30
    let headingSubheadingMargin: CGFloat = 22
    private var iconImageViews = [UIImageView]()
    
    var headingInset: CGFloat {
        if E.isIPhone6OrSmaller {
            return 32
        } else {
            return 64
        }
    }
    
    var subheadingInset: CGFloat {
        return headingInset - 10
    }

    var videoClipContainerTopInset: CGFloat {
        if E.isIPhone6OrSmaller {
            return 0
        } else {
            return 30
        }
    }
    
    // Used to ensure we only animate the landing page on the first appearance.
    var appearanceCount: Int = 0
    
    let pageCount: Int = 1

    let finalPageIndex = 1
    
    // Whenever we're animating from page to page this is set to true
    // to prevent additional taps on the Next button during the transition.
    var isPaging: Bool = false {
        didSet {
            [topButton, bottomButton, skipButton, backButton].forEach { (button) in
                button.isUserInteractionEnabled = !isPaging
            }
        }
    }
    
    var pageIndex: Int = 0 {
        didSet {
            // Show/hide the Back and Skip buttons.
            let backAlpha: CGFloat = (pageIndex == 1) ? 1.0 : 0.0
            let skipAlpha: CGFloat = (pageIndex == 1) ? 1.0 : 0.0

            let delay = (pageIndex == 1) ? firstTransitionDelay : 0.0
            
            UIView.animate(withDuration: 0.3, delay: delay, options: .curveEaseIn, animations: { 
                self.backButton.alpha = backAlpha
                self.skipButton.alpha = skipAlpha                                
            }, completion: nil)
            
            switch pageIndex {
            case finalPageIndex:
                logEvent(.appeared, screen: .finalPage)
            default:
                break
            }
        }
    }
    
    var lastPageIndex: Int { return pageCount - 1 }
    
    // CTA's that appear at the bottom of the screen
    private let topButton = BRDButton(title: "", type: .primary)
    private let middleButton = BRDButton(title: "", type: .darkOpaque)
    private let bottomButton = BRDButton(title: "", type: .darkOpaque)
    private let nextButton = BRDButton(title: S.OnboardingScreen.next, type: .primary)
    
    // Constraints used to show and hide the bottom buttons.
    private var topButtonAnimationConstraint: NSLayoutConstraint?
    private var middleButtonAnimationConstraint: NSLayoutConstraint?
    private var bottomButtonAnimationConstraint: NSLayoutConstraint?
    private var nextButtonAnimationConstraint: NSLayoutConstraint?
    
    private let backButton = UIButton(type: .custom)
    private let skipButton = UIButton(type: .custom)
        
    private let cloudBackupExists: Bool
    
    required init(doesCloudBackupExist: Bool, didExitOnboarding: DidExitOnboardingWithAction?) {
        self.cloudBackupExists = doesCloudBackupExist
        super.init(nibName: nil, bundle: nil)
        didExitWithAction = didExitOnboarding
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func exitWith(action exitAction: OnboardingExitAction) {
        didExitWithAction?(exitAction)
    }
    
    @objc private func backTapped(sender: Any) {
        
        let headingLabel = headingLabels[pageIndex]
        let subheadingLabel = subheadingLabels[pageIndex]
        let headingConstraint = headingConstraints[pageIndex]
        
        UIView.animate(withDuration: 0.4, animations: { 
            // make sure next or top/bottom buttons are animated out
            self.topButtonAnimationConstraint?.constant = self.buttonsHiddenYOffset
            self.nextButtonAnimationConstraint?.constant = self.buttonsHiddenYOffset
            
            headingLabel.alpha = 0
            subheadingLabel.alpha = 0
            headingConstraint.constant -= (self.headingLabelAnimationOffset)
            
            for videoContainer in self.videoContainerViews {
                videoContainer.alpha = 0
            }
            
            self.view.layoutIfNeeded()
        }, completion: { _ in
            self.reset(completion: { 
                self.animateLandingPage()
            })
        })
        
        logEvent(.backButton, screen: .globePage)
    }
    
    @objc private func skipTapped(sender: Any) {
        exitWith(action: .createWallet)
        logEvent(.skipButton, screen: .globePage)
    }
    
    private func reset(completion: @escaping () -> Void) {
        
        for (index, constraint) in self.headingConstraints.enumerated() {
            constraint.constant = (index == 0) ? 0 : -(headingLabelAnimationOffset)
        }
                
        self.subheadingConstraints.forEach { $0.constant = headingSubheadingMargin }
        self.headingLabels.forEach { $0.alpha = 0 }
        self.subheadingLabels.forEach { $0.alpha = 0 }
        
        view.layoutIfNeeded()
        
        self.videoPlayers.removeAll()
        self.videoLayers.removeAll()

        self.videoContainerViews.forEach { $0.removeFromSuperview() }
        self.videoContainerViews.removeAll()
        
        self.pageIndex = 0

        self.topButton.title = topButtonText(pageIndex: 0)
        self.bottomButton.title = bottomButtonText(pageIndex: 0)

        completion()        
    }
    
    private func setUpLogo() {
        logoImageView.alpha = 0
        
        self.view.addSubview(logoImageView)
        
        let screenHeight = UIScreen.main.bounds.height
        let offset = (screenHeight / 4.0) + 20
        
        logoImageView.constrain([
            logoImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0),
            logoImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -(offset))
            ])
        
    }
    
    private func hideStarburstIcons() {
        iconImageViews.forEach { $0.layer.removeAllAnimations() }
        UIView.animate(withDuration: 0.1, animations: { [weak self] in
            self?.iconImageViews.forEach { $0.alpha = 0.0 }
        })
    }
    
    private func setUpPages() {
        pages.append(OnboardingPage(heading: S.OnboardingScreen.pageOneTitle,
                                    subheading: "", 
                                    videoClip: ""))
    }
        
    private func makeHeadingLabel(text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        
        label.alpha = 0
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = color
        label.font = font
        label.text = text
        
        return label
    }
    
    private func headingFont(for page: OnboardingPage) -> UIFont {
        if !E.isIPhone6OrSmaller || page.subheading.isEmpty {
            return UIFont.onboardingHeading()
        } else {
            return UIFont.onboardingSmallHeading()
        }
    }
        
    private func setUpHeadingLabels() {

        for (index, page) in pages.enumerated() {
            
            // create the headings
            let headingLabel = makeHeadingLabel(text: page.heading, 
                                                font: headingFont(for: page),
                                                color: .onboardingHeadingText)
            view.addSubview(headingLabel)
            
            let offset: CGFloat = (index == 0) ? 0 : -(self.headingLabelAnimationOffset)
            var animationConstraint = headingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, 
                                                                            constant: offset)
            var leading = headingLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, 
                                                                constant: headingInset)
            var trailing = headingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, 
                                                                  constant: -(headingInset))
            
            headingLabel.constrain([animationConstraint, leading, trailing])
            
            headingConstraints.append(animationConstraint)
            headingLabels.append(headingLabel)

            // create the subheadings
            let subheadingLabel = makeHeadingLabel(text: page.subheading, 
                                                   font: UIFont.onboardingSubheading(),
                                                   color: .onboardingSubheadingText)
            view.addSubview(subheadingLabel)
            
            animationConstraint = subheadingLabel.topAnchor.constraint(equalTo: headingLabel.bottomAnchor, 
                                                                       constant: headingSubheadingMargin)
            leading = subheadingLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, 
                                                               constant: subheadingInset)
            trailing = subheadingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, 
                                                                 constant: -(subheadingInset))
            
            subheadingLabel.constrain([animationConstraint, leading, trailing])
            
            subheadingConstraints.append(animationConstraint)
            subheadingLabels.append(subheadingLabel)
        }
    }
    
    private func topButtonText(pageIndex: Int) -> String {
        if pageIndex == 0 {
            if cloudBackupExists {
                return S.CloudBackup.restoreButton
            } else {
                return S.OnboardingScreen.getStarted
            }
        }
        return ""
    }

    private func middleButtonText(pageIndex: Int) -> String {
        //no middle button if no backup detected
        if pageIndex == 0 && cloudBackupExists {
            return S.CloudBackup.recoverButton
        }
        return ""
    }
    
    private func bottomButtonText(pageIndex: Int) -> String {
        if pageIndex == 0 {
            if cloudBackupExists {
                return S.CloudBackup.createButton
            } else {
                return S.OnboardingScreen.restoreWallet
            }
        }
        return ""
    }
    
    let buttonHeight: CGFloat = 48.0
    let buttonsVerticalMargin: CGFloat = 12.0
    let bottomButtonBottomMargin: CGFloat = 10.0
    let nextButtonBottomMargin: CGFloat = 20.0
        
    private var buttonsHiddenYOffset: CGFloat {
        return (buttonHeight + 40.0)
    }
    
    private var bottomButtonVisibleYOffset: CGFloat {
        return -buttonsVerticalMargin
    }
    
    private var middleButtonVisibleYOffset: CGFloat {
        return -(buttonsVerticalMargin*2 + buttonHeight)
    }
    
    private var topButtonVisibleYOffset: CGFloat {
        if cloudBackupExists {
            return middleButtonVisibleYOffset - (buttonsVerticalMargin + buttonHeight)
        } else {
            return middleButtonVisibleYOffset
        }
    }
        
    private var nextButtonVisibleYOffset: CGFloat {
        return -nextButtonBottomMargin
    }
    
    private func setUpBottomButtons() {
        // Set the buttons up for the first page; the title text will be updated
        // once we reach the last page of the onboarding flow.
        topButton.title = topButtonText(pageIndex: 0)
        middleButton.title = middleButtonText(pageIndex: 0)
        bottomButton.title = bottomButtonText(pageIndex: 0)
        
        view.addSubview(topButton)
        view.addSubview(middleButton)
        view.addSubview(bottomButton)
        view.addSubview(nextButton)
        
        let buttonLeftRightMargin: CGFloat = 24
        let buttonHeight: CGFloat = 48
        
        // Position the top button just below the bottom of the view (or safe area / notch) to start with
        // so that we can animate it up into view.
        topButtonAnimationConstraint = topButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                                      constant: buttonsHiddenYOffset)
        nextButtonAnimationConstraint = nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                                            constant: buttonsHiddenYOffset)
        middleButtonAnimationConstraint = middleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                                      constant: buttonsHiddenYOffset)
        bottomButtonAnimationConstraint = bottomButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                                            constant: buttonsHiddenYOffset)
        topButton.constrain([
            topButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0),
            topButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: buttonLeftRightMargin),
            topButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -buttonLeftRightMargin),                
            topButton.heightAnchor.constraint(equalToConstant: buttonHeight),
            topButtonAnimationConstraint
            ])
        
        middleButton.constrain([
            middleButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0),
            middleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: buttonLeftRightMargin),
            middleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -buttonLeftRightMargin),
            middleButton.heightAnchor.constraint(equalToConstant: buttonHeight),
            middleButtonAnimationConstraint
            ])
        
        bottomButton.constrain([
            bottomButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0),
            bottomButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: buttonLeftRightMargin),
            bottomButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -buttonLeftRightMargin), 
            bottomButton.heightAnchor.constraint(equalToConstant: buttonHeight),
            bottomButtonAnimationConstraint
            ])
        
        nextButton.constrain([
            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: buttonLeftRightMargin),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -buttonLeftRightMargin), 
            nextButton.heightAnchor.constraint(equalToConstant: buttonHeight),
            nextButtonAnimationConstraint
            ])        
        
        topButton.tap = { [unowned self] in
            self.topButtonTapped()
        }
        
        middleButton.tap = { [unowned self] in
            self.middleButtonTapped()
        }
        
        bottomButton.tap = { [unowned self] in
            self.bottomButtonTapped()
        }
        
        nextButton.tap = { [unowned self] in
            self.animateToNextPage()
        }
    }
    
    private func addBackAndSkipButtons() {
        let image = UIImage(named: "BackArrowWhite")
        
        backButton.alpha = 0
        skipButton.alpha = 0
        
        backButton.setImage(image, for: .normal)
        backButton.addTarget(self, action: #selector(backTapped(sender:)), for: .touchUpInside)
        
        view.addSubview(backButton)
        
        var topAnchor: NSLayoutYAxisAnchor?
        var leadingAnchor: NSLayoutXAxisAnchor?
        
        topAnchor = view.safeAreaLayoutGuide.topAnchor
        leadingAnchor = view.safeAreaLayoutGuide.leadingAnchor

        backButton.constrain([
            backButton.topAnchor.constraint(equalTo: topAnchor!, constant: 30),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor!, constant: C.padding[2]),
            backButton.heightAnchor.constraint(equalToConstant: 13),
            backButton.widthAnchor.constraint(equalToConstant: 20)
            ])
        
        skipButton.setTitle(S.OnboardingScreen.skip, for: .normal)
        skipButton.titleLabel?.font = UIFont.onboardingSkipButton()
        skipButton.setTitleColor(.onboardingSkipButtonTitle, for: .normal)
        skipButton.addTarget(self, action: #selector(skipTapped(sender:)), for: .touchUpInside)
        
        view.addSubview(skipButton)
        
        var trailingAnchor: NSLayoutXAxisAnchor?
        
        trailingAnchor = view.safeAreaLayoutGuide.trailingAnchor
        
        skipButton.constrain([
            skipButton.trailingAnchor.constraint(equalTo: trailingAnchor!, constant: -30),
            skipButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor, constant: 0)
            ])
    }
            
    private func animateLandingPage() {

        let delay = 0.2
        let duration = 0.3//0.5
                
        // animate heading position
        let constraint = headingConstraints[0]
        UIView.animate(withDuration: duration, delay: delay, options: UIView.AnimationOptions.curveEaseInOut, animations: {
            constraint.constant = -(self.headingLabelAnimationOffset)
        })            
            
        // animate heading fade-in
        let label = headingLabels[0]
        UIView.animate(withDuration: duration + 0.2, delay: delay * 2.0, options: UIView.AnimationOptions.curveEaseInOut, animations: {
            label.alpha = 1
        })            
        
        topButton.alpha = 0
        middleButton.alpha = 0
        bottomButton.alpha = 0
        
        // fade-in animation for the buttons
        UIView.animate(withDuration: (duration * 1.5), delay: (delay * 2.0), options: UIView.AnimationOptions.curveEaseIn, animations: { 
            self.topButton.alpha = 1
            self.bottomButton.alpha = 1
            self.middleButton.alpha = 1
        })

        // slide-up animation for the top button
        UIView.animate(withDuration: (duration * 1.5), delay: delay, options: UIView.AnimationOptions.curveEaseInOut, animations: { 
            self.topButtonAnimationConstraint?.constant = self.topButtonVisibleYOffset
            self.view.layoutIfNeeded()
        })
        
        if self.cloudBackupExists {
            middleButtonAnimationConstraint?.constant = (buttonsVerticalMargin * 2.0)
            view.layoutIfNeeded()
            
            // slide-up animation for the middle button
            UIView.animate(withDuration: (duration * 1.5), delay: delay * 1.5, options: UIView.AnimationOptions.curveEaseInOut, animations: {
                self.middleButtonAnimationConstraint?.constant = self.middleButtonVisibleYOffset
                self.view.layoutIfNeeded()
            })
        }
        
        bottomButtonAnimationConstraint?.constant = (buttonsVerticalMargin * 3.0)
        view.layoutIfNeeded()
        
        // slide-up animation for the bottom button
        UIView.animate(withDuration: (duration * 1.5), delay: (delay * 2.0), options: UIView.AnimationOptions.curveEaseInOut, animations: { 
            // animate the bottom button up to its correct offset relative to the top button
            self.bottomButtonAnimationConstraint?.constant = self.bottomButtonVisibleYOffset
            self.view.layoutIfNeeded()
        })
    }
        
    private func animateToNextPage() {
        guard !isPaging, pageIndex >= 0, pageIndex < pageCount else {
            return
        }
        
        if pageIndex == lastPageIndex {
            exitWith(action: .createWallet)
            return
        }
        
        isPaging = true
        
        let nextIndex = pageIndex + 1
        
        let pageAnimationDuration = 0.6//1.0
        let delay = animationDelays[nextIndex]
        
        let currentHeadingLabel = headingLabels[pageIndex]
        let nextHeadingLabel = headingLabels[nextIndex]
        
        let currentSubheadingLabel = subheadingLabels[pageIndex]
        let nextSubheadingLabel = subheadingLabels[nextIndex]
        
        let currentHeadingConstraint = headingConstraints[pageIndex]
        let nextHeadingConstraint = headingConstraints[nextIndex]
        
        let fadeInOffsetFactor = fadeInOffsetFactors[nextIndex]
        
        if nextIndex == 1 {
            hideStarburstIcons()
        }
        
        UIView.animateKeyframes(withDuration: pageAnimationDuration, delay: delay, 
                                options: .calculationModeCubic, animations: { [weak self] in
                                    guard let `self` = self else { return }
                                    
                                    // Fade out the logo.
                                    if self.logoImageView.alpha == 1 {
                                        UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.4) { 
                                            self.logoImageView.alpha = 0
                                        }
                                    }
                                    
                                    UIView.addKeyframe(withRelativeStartTime: 0.1, relativeDuration: 0.4) { 
                                        currentHeadingLabel.alpha = 0
                                        currentSubheadingLabel.alpha = 0
                                        currentHeadingConstraint.constant -= (self.headingLabelAnimationOffset)
                                        currentHeadingLabel.superview?.layoutIfNeeded()
                                    }
                                    
                                    UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5, animations: { 
                                        nextHeadingLabel.alpha = 1
                                        nextSubheadingLabel.alpha = 1
                                        nextHeadingConstraint.constant = -(self.headingLabelAnimationOffset * fadeInOffsetFactor)
                                        nextHeadingLabel.superview?.layoutIfNeeded()
                                    })
                                    
                                    if self.pageIndex == 0 {
                                        
                                        // Animate buttons down
                                        [self.topButtonAnimationConstraint,
                                         self.middleButtonAnimationConstraint,
                                         self.bottomButtonAnimationConstraint].forEach { constraint in
                                            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5, animations: {
                                                constraint?.constant = self.buttonsHiddenYOffset
                                                self.view.layoutIfNeeded()
                                            })
                                        }
                                    }
                                    
            }, completion: { [weak self] _ in
                guard let `self` = self else { return }

                let nextIndex = min(self.pageIndex + 1, self.pageCount - 1)
                
                let finishTransition: () -> Void  = {
                    self.pageIndex = nextIndex
                    self.isPaging = false
                }
                
                // Animate the Next button after the other animations are finished to give the video
                // clip a bit more time to finish. The first clip is a bit longer than the others and
                // includes a slick bitcoin transfer animation at the end.
                if nextIndex == 1 {
                    //0.5
                    UIView.animate(withDuration: 0.3, delay: 0.0, options: .curveEaseInOut, animations: {
                        self.nextButtonAnimationConstraint?.constant = self.nextButtonVisibleYOffset
                        self.view.layoutIfNeeded()                    
                    }, completion: { _ in
                        finishTransition()
                    })
                } else {
                    finishTransition()
                }
        })
    }
        
    private func topButtonTapped() {
        if self.pageIndex == 0 {
            if cloudBackupExists {
                exitWith(action: .restoreCloudBackup)
            } else {
               // 'Create new wallet'
               self.animateToNextPage()
               logEvent(.getStartedButton, screen: .landingPage)
            }
        }
    }
    
    private func middleButtonTapped() {
        showAlert(message: S.CloudBackup.recoverWarning,
                  button: S.CloudBackup.recoverButton,
                  completion: { [weak self] in
                    self?.exitWith(action: .restoreWallet)
                    self?.logEvent(.restoreWalletButton, screen: .landingPage)
                })
    }
    
    private func bottomButtonTapped() {
        if pageIndex == 0 {
            if cloudBackupExists {
                showAlert(message: S.CloudBackup.createWarning, button: S.CloudBackup.createButton, completion: { [weak self] in
                    self?.animateToNextPage()
                })
            } else {
               // 'Restore wallet'
               exitWith(action: .restoreWallet)
               logEvent(.restoreWalletButton, screen: .landingPage)
            }
        } else if pageIndex == self.lastPageIndex {
            // 'I'll browse first'
            exitWith(action: .createWallet)
            logEvent(.browseFirstButton, screen: .finalPage)
        }
    }
                         
    private func setupSubviews() {
        setUpHeadingLabels()
        
        setUpBottomButtons()
        addBackAndSkipButtons()        
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if appearanceCount == 0 {
            animateLandingPage()
            logEvent(.appeared, screen: .landingPage)
        }
        appearanceCount += 1
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Make sure we set this in case the user taps Restore Wallet, then comes
        // back to the onboarding flow in case the nav bar hidden status is changed.
        self.navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // make sure the video layers' frames match the container view
        var index = 0
        for videoContainer in videoContainerViews {
            let videoLayer = videoLayers[index]
            videoLayer.frame = videoContainer.frame
            index += 1
        }        
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationController?.isNavigationBarHidden = true
        view.backgroundColor = Theme.primaryBackground
                
        setUpLogo()
        setUpPages()
        setupSubviews()
    }
    
    private func showAlert(message: String, button: String, completion: @escaping () -> Void) {
        let alert = UIAlertController(title: S.Alert.warning,
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: S.Button.cancel, style: .cancel, handler: {_ in }))
        alert.addAction(UIAlertAction(title: button, style: .default, handler: {_ in
            completion()
        }))
        present(alert, animated: true, completion: nil)
    }
}

// analytics
extension OnboardingViewController: Trackable {
    func logEvent(_ event: Event, screen: Screen) {
        saveEvent(context: .onboarding, screen: screen, event: event)
    }
}
