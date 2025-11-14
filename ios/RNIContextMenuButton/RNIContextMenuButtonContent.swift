//
//  RNIContextMenuButtonContent.swift
//  react-native-ios-context-menu
//
//  Created by Dominic Go on 8/24/24.
//

import UIKit
import DGSwiftUtilities
import ContextMenuAuxiliaryPreview
import react_native_ios_utilities


@objc(RNIContextMenuButtonContent)
public final class RNIContextMenuButtonContent: UIButton, RNIContentView {

  // MARK: - Embedded Types
  // ----------------------
  
  public enum Events: String, CaseIterable {
    case onDidSetViewID;
    
    case onMenuWillShow;
    case onMenuWillHide;
    case onMenuWillCancel;
    case onMenuDidShow;
    case onMenuDidHide;
    case onMenuDidCancel;
    case onPressMenuItem;
    case onRequestDeferredElement;
  };
  
  // MARK: - Static Properties
  // -------------------------
  
  public static var propKeyPathMap: Dictionary<String, PartialKeyPath<RNIContextMenuButtonContent>> = [
    "menuConfig": \.menuConfigProp,
    "isContextMenuEnabled": \.isContextMenuEnabled,
    "isMenuPrimaryAction": \.isMenuPrimaryAction,
  ];
  
  // MARK: Properties
  // ----------------
  
  var _didSetup = false;
  
  var _deferredElementCompletionMap:
    [String: RNIDeferredMenuElement.CompletionHandler] = [:];

  weak var navEventsVC: RNINavigationEventsReportingViewController?;
  var longPressGestureRecognizer: UILongPressGestureRecognizer!;
  var tapGestureRecognizer: UITapGestureRecognizer?;
    
  // MARK: Public Properties
  // -----------------------
  
   /// Keep track on whether or not the context menu is currently visible.
  internal(set) public var isContextMenuVisible = false;
  
  // TODO: Fix 
  /// This is set to `true` when the menu is open and an item is pressed, and
  /// is immediately set back to `false` once the menu close animation
  /// finishes.
  internal(set) public var didPressMenuItem = false;
  
  /// Whether or not the current view was successfully added as child VC
  private(set) public var didAttachToParentVC = false;
  
  // MARK: - Properties - RNIContentViewDelegate
  // -------------------------------------------
  
  public weak var parentReactView: RNIContentViewParentDelegate?;
  
  // MARK: Properties - Props
  // ------------------------
  
  public var reactProps: NSDictionary = [:];
  
  private(set) public var menuConfig: RNIMenuItem?;
  @objc public var menuConfigProp: NSDictionary? {
    willSet {
      guard let newValue = newValue as? Dictionary<String, Any>,
            newValue.count > 0,
            
            let menuConfig = RNIMenuItem(dictionary: newValue)
      else {
        self.menuConfig = nil;
        return;
      };
      
      menuConfig.delegate = self;
      self.updateContextMenuIfVisible(with: menuConfig);
      
      // cleanup `deferredElementCompletionMap`
      self.cleanupOrphanedDeferredElements(currentMenuConfig: menuConfig);
      
      // update config
      self.menuConfig = menuConfig;
      
      guard #available(iOS 14.0, *) else {
        return;
      };
      
      let menu = self.createMenu(with: menuConfig);
      self.menu = menu;
    }
  };
  
  @objc public var isContextMenuEnabled = true {
    willSet {
      guard #available(iOS 14.0, *) else { return };
      self.isContextMenuInteractionEnabled = newValue;
    }
  };
  
  @objc public var isMenuPrimaryAction = false {
    didSet {
      // DON'T use showsMenuAsPrimaryAction as it automatically adds pill styling
      // Instead, we'll use a tap gesture recognizer to present the menu
      self._setupMenuPrimaryAction();
    }
  };
  
  // MARK: Init
  // ----------
  
  public static func createInstance(
    sender: RNIContentViewParentDelegate,
    frame: CGRect
  ) -> RNIContextMenuButtonContent {
    
    return .init();
  };
  
  // MARK: Functions - Setup
  // -----------------------
 
  func _setupIfNeeded(){
    guard !self._didSetup else { return };
    self._didSetup = true;

    self.isEnabled = true;
    self.isAccessibilityElement = false;

    // Clip any content that extends beyond bounds
    self.clipsToBounds = true;

    // CRITICAL: Keep autoresizing enabled so React Native can set frame
    // But prevent the button from resisting size changes
    self.translatesAutoresizingMaskIntoConstraints = true
    self.autoresizesSubviews = false

    // CRITICAL: Use required priority to prevent expansion
    // This forces the button to stay at its intrinsic content size
    self.setContentHuggingPriority(.required, for: .horizontal)
    self.setContentHuggingPriority(.required, for: .vertical)
    self.setContentCompressionResistancePriority(.required, for: .horizontal)
    self.setContentCompressionResistancePriority(.required, for: .vertical)

    // Disable all automatic insets and padding
    if #available(iOS 15.0, *) {
      self.configuration?.contentInsets = .zero
      self.configurationUpdateHandler = nil
    }

    // Remove button styling
    if #available(iOS 15.0, *) {
      self._removeButtonStyling();
    } else {
      self.backgroundColor = .clear
    }

    // Setup menu primary action if needed
    self._setupMenuPrimaryAction();
  };

  func _removeButtonStyling() {
    guard #available(iOS 15.0, *) else { return };

    // Prevent automatic configuration updates
    self.automaticallyUpdatesConfiguration = false;

    // Use .plain() configuration as per Apple's guidance for menu buttons
    // Setting to nil causes UIButton to use default styling
    var config = UIButton.Configuration.plain();

    // Remove ALL styling and padding
    config.background.backgroundColor = .clear;
    config.background.backgroundColorTransformer = nil;
    config.background.visualEffect = nil;
    config.background.strokeColor = .clear;
    config.background.strokeWidth = 0;
    config.background.cornerRadius = 0;
    config.baseBackgroundColor = .clear;
    config.baseForegroundColor = .clear;

    // CRITICAL: Set contentInsets to zero and use small size
    config.contentInsets = .zero;
    config.imagePadding = 0;
    config.titlePadding = 0;

    // Disable macCatalyst hover effects
    config.macIdiomStyle = .automatic;

    self.configuration = config;
    self.backgroundColor = .clear;
    self.tintColor = .clear;

    // Force layout update
    self.setNeedsLayout();
    self.layoutIfNeeded();
  };

  func _setupMenuPrimaryAction() {
    guard #available(iOS 14.0, *) else { return };

    if self.isMenuPrimaryAction {
      // DON'T use showsMenuAsPrimaryAction - it adds pill background
      // Instead, add a tap gesture to present the menu manually
      self.showsMenuAsPrimaryAction = false;

      if self.tapGestureRecognizer == nil {
        let tapGesture = UITapGestureRecognizer(
          target: self,
          action: #selector(self.handleTapGesture(_:))
        );
        tapGesture.numberOfTapsRequired = 1;
        self.addGestureRecognizer(tapGesture);
        self.tapGestureRecognizer = tapGesture;
      }
    } else {
      // Remove tap gesture if isMenuPrimaryAction is false
      if let tapGesture = self.tapGestureRecognizer {
        self.removeGestureRecognizer(tapGesture);
        self.tapGestureRecognizer = nil;
      }
      self.showsMenuAsPrimaryAction = false;
    }
  };

  // Override intrinsicContentSize to use subview size (React Native children)
  // This prevents the button from expanding to fill available space
  public override var intrinsicContentSize: CGSize {
    // Calculate size based on subviews (React Native children)
    var maxWidth: CGFloat = 0
    var maxHeight: CGFloat = 0

    for subview in self.subviews {
      let subviewSize = subview.intrinsicContentSize
      if subviewSize.width != UIView.noIntrinsicMetric {
        maxWidth = max(maxWidth, subviewSize.width)
      } else {
        maxWidth = max(maxWidth, subview.bounds.width)
      }

      if subviewSize.height != UIView.noIntrinsicMetric {
        maxHeight = max(maxHeight, subviewSize.height)
      } else {
        maxHeight = max(maxHeight, subview.bounds.height)
      }
    }

    // If we have valid dimensions, use them
    if maxWidth > 0 && maxHeight > 0 {
      return CGSize(width: maxWidth, height: maxHeight)
    }

    // If bounds are set, use them (React Native frame)
    if self.bounds.size.width > 0 && self.bounds.size.height > 0 {
      return self.bounds.size
    }

    // Fallback to no intrinsic metric
    return CGSize(
      width: UIView.noIntrinsicMetric,
      height: UIView.noIntrinsicMetric
    )
  };

  // Override sizeThatFits to respect the current bounds
  public override func sizeThatFits(_ size: CGSize) -> CGSize {
    return self.bounds.size
  };

  // Override layoutSubviews to prevent UIButton from resizing
  public override func layoutSubviews() {
    let originalBounds = self.bounds
    super.layoutSubviews()

    // Restore the bounds set by React Native if UIButton tried to change them
    if self.bounds != originalBounds {
      self.bounds = originalBounds
    }

    // Remove any background views that UIButton adds for the pill styling
    // UIButton adds internal subviews for the pill background - remove them
    if #available(iOS 15.0, *) {
      for subview in self.subviews {
        // Check if this is a UIButton internal background view
        let className = String(describing: type(of: subview))
        if className.contains("Background") ||
           className.contains("Visual") ||
           className.contains("Effect") {
          subview.isHidden = true
          subview.alpha = 0
        }
      }
    }

    // Invalidate intrinsic content size when layout changes
    self.invalidateIntrinsicContentSize()
  };

  // Override bounds setter to lock the size
  private var _lockedBounds: CGRect?
  public override var bounds: CGRect {
    get {
      return super.bounds
    }
    set {
      var finalBounds = newValue

      // Enforce maximum size to prevent button expansion
      // This prevents UIButton from creating massive pills
      let maxDimension: CGFloat = 50 // Allow max 50pt in any direction
      if finalBounds.size.width > maxDimension {
        finalBounds.size.width = maxDimension
      }
      if finalBounds.size.height > maxDimension {
        finalBounds.size.height = maxDimension
      }

      // Store the first valid bounds set by React Native
      if _lockedBounds == nil && finalBounds != .zero {
        _lockedBounds = finalBounds
      }

      // Use locked bounds if we have them, otherwise use the constrained bounds
      if let locked = _lockedBounds, locked != .zero {
        super.bounds = locked
      } else {
        super.bounds = finalBounds
      }
    }
  };

  // Override frame setter to prevent UIButton from expanding
  // This is CRITICAL as React Native sets frame, not just bounds
  private var _lockedFrame: CGRect?
  public override var frame: CGRect {
    get {
      return super.frame
    }
    set {
      var finalFrame = newValue

      // Enforce maximum size to prevent button pill expansion
      let maxDimension: CGFloat = 50 // Max 50pt in any direction
      if finalFrame.size.width > maxDimension {
        finalFrame.size.width = maxDimension
      }
      if finalFrame.size.height > maxDimension {
        finalFrame.size.height = maxDimension
      }

      // Lock the first valid frame from React Native
      if _lockedFrame == nil && finalFrame.size != .zero {
        _lockedFrame = finalFrame
      }

      // Preserve the origin, but lock the size
      if let locked = _lockedFrame, locked.size != .zero {
        var constrainedFrame = finalFrame
        constrainedFrame.size = locked.size
        super.frame = constrainedFrame
      } else {
        super.frame = finalFrame
      }
    }
  };

  // MARK: Functions
  // ---------------
  
  func createMenu(with menuConfig: RNIMenuItem? = nil) -> UIMenu? {
    guard let menuConfig = menuConfig ?? self.menuConfig
    else { return nil };
    
    return menuConfig.createMenu(actionItemHandler: { [weak self] in
      // A. menu item has been pressed...
      self?.handleOnPressMenuActionItem(dict: $0, action: $1);
      
    }, deferredElementHandler: { [weak self] in
      // B. deferred element is requesting for items to load...
      self?.handleOnDeferredElementRequest(deferredID: $0, completion: $1);
    });
  };
  
  func updateContextMenuIfVisible(with menuConfig: RNIMenuItem){
    guard #available(iOS 14.0, *),
          self.isContextMenuVisible,
          
          let interaction = self.contextMenuInteraction,
          let menu = self.createMenu(with: menuConfig)
    else { return };
    
    // context menu is open, update the menu items
    interaction.updateVisibleMenu { _ in
      return menu;
    };
  };
  
  func handleOnPressMenuActionItem(
    dict: [String: Any],
    action: UIAction
  ){
    self.didPressMenuItem = true;
    
    self.dispatchEvent(
      for: .onPressMenuItem,
      withPayload: dict
    );
  };
  
  func handleOnDeferredElementRequest(
    deferredID: String,
    completion: @escaping RNIDeferredMenuElement.CompletionHandler
  ){
    // register completion handler
    self._deferredElementCompletionMap[deferredID] = completion;
    
    // notify js that a deferred element needs to be loaded
    self.dispatchEvent(
      for: .onRequestDeferredElement,
      withPayload: [
        "deferredID": deferredID,
      ]
    );
  };
  
  @objc func handleLongPressGesture(_ sender: UILongPressGestureRecognizer){
    // no-op
  };

  @objc func handleTapGesture(_ sender: UITapGestureRecognizer) {
    guard #available(iOS 14.0, *),
          sender.state == .ended,
          self.isMenuPrimaryAction,
          !self.isContextMenuVisible
    else { return };

    // Present the menu programmatically on tap
    try? self.presentMenu();
  };
  
  func attachToParentVC(){
    guard !self.didAttachToParentVC else { return };
        
    // find the nearest parent view controller
    let parentVC = self.recursivelyFindNextResponder(
      withType: UIViewController.self
    );
    
    guard let parentVC = parentVC else { return };
    self.didAttachToParentVC = true;
    
    let childVC = RNINavigationEventsReportingViewController();
    childVC.view = self;
    childVC.delegate = self;
    childVC.parentVC = parentVC;
    
    self.navEventsVC = childVC;

    parentVC.addChild(childVC);
    childVC.didMove(toParent: parentVC);
  };
  
  func cleanupOrphanedDeferredElements(currentMenuConfig: RNIMenuItem) {
    guard self._deferredElementCompletionMap.count > 0
    else { return };
    
    let currentDeferredElements = RNIMenuElement.recursivelyGetAllElements(
      from: currentMenuConfig,
      ofType: RNIDeferredMenuElement.self
    );
      
    // get the deferred elements that are not in the new config
    let orphanedKeys = self._deferredElementCompletionMap.keys.filter { deferredID in
      !currentDeferredElements.contains {
        $0.deferredID == deferredID
      };
    };
    
    // cleanup
    orphanedKeys.forEach {
      self._deferredElementCompletionMap.removeValue(forKey: $0);
    };
  };
  
  func detachFromParentVCIfAny(){
    guard !self.didAttachToParentVC,
          let navEventsVC = self.navEventsVC
    else { return };
    
    navEventsVC.willMove(toParent: nil);
    navEventsVC.removeFromParent();
    navEventsVC.view.removeFromSuperview();
  };
  
  // MARK: - Functions - View Module Commands
  // ----------------------------------------
  
  public func dismissMenu() throws {
    guard #available(iOS 14.0, *) else {
      throw RNIContextMenuError(
        errorCode: .guardCheckFailed,
        description: "Unsupported, requires iOS 14+"
      );
    };
    
    guard let contextMenuInteraction = self.contextMenuInteraction else {
      throw RNIContextMenuError.init(
        errorCode: .unexpectedNilValue,
        description: "contextMenuInteraction is nil"
      );
    };
    
    contextMenuInteraction.dismissMenu();
  };
  
  public func provideDeferredElements(
    id deferredID: String,
    menuElements rawMenuElements: [RNIMenuElement]
  ) throws {
    
    guard let completionHandler = self._deferredElementCompletionMap[deferredID]
    else {
      throw RNIContextMenuError(
        description: "No matching deferred completion handler found for deferredID",
        extraDebugValues: ["deferredID": deferredID]
      );
    };
    
    // create menu elements
    let menuElements = rawMenuElements.compactMap { menuElement in
      menuElement.createMenuElement(
        actionItemHandler: { [unowned self] in
          self.handleOnPressMenuActionItem(dict: $0, action: $1);
          
        }, deferredElementHandler: { [unowned self] in
          self.handleOnDeferredElementRequest(deferredID: $0, completion: $1);
        }
      );
    };
    
    // add menu elements
    completionHandler(menuElements);
  
    // cleanup
    self._deferredElementCompletionMap.removeValue(forKey: deferredID);
  };
  
  func presentMenu() throws {
    guard #available(iOS 14.0, *) else {
      throw RNIContextMenuError(
        errorCode: .guardCheckFailed,
        description: "Unsupported, requires iOS 14+"
      );
    };
    
    guard self.isContextMenuEnabled else {
      throw RNIContextMenuError.init(
        errorCode: .guardCheckFailed,
        description: "Context menu is disabled"
      );
    };
    
    guard !self.isContextMenuVisible else {
      throw RNIContextMenuError.init(
        errorCode: .guardCheckFailed,
        description: "Context menu is already visible"
      );
    };
    
    guard let contextMenuInteraction = self.contextMenuInteraction else {
      throw RNIContextMenuError.init(
        errorCode: .unexpectedNilValue,
        description: "contextMenuInteraction is nil"
      );
    };
    
    guard let contextMenuInteractionWrapper =
            ContextMenuInteractionWrapper(objectToWrap: contextMenuInteraction)
    else {
      throw RNIContextMenuError.init(
        errorCode: .unexpectedNilValue,
        description: "Unable to create ContextMenuInteractionWrapper"
      );
    };
    
    try contextMenuInteractionWrapper.presentMenuAtLocation(point: .zero);
  };
};

// MARK: - RNIContextMenuButtonDelegate+RNIContentViewDelegate
// --------------------------------------------------

extension RNIContextMenuButtonContent: RNIContentViewDelegate {

  public typealias KeyPathRoot = RNIContextMenuButtonContent;

  // MARK: Paper + Fabric
  // --------------------
  
  public func notifyOnInit(sender: RNIContentViewParentDelegate) {
    // no-op
  };
    
  public func notifyOnMountChildComponentView(
    sender: RNIContentViewParentDelegate,
    childComponentView: UIView,
    index: NSInteger,
    superBlock: () -> Void
  ) {
    self.addSubview(childComponentView);
    // Invalidate intrinsic content size when child is mounted
    self.invalidateIntrinsicContentSize();
  };
  
  public func notifyOnUnmountChildComponentView(
    sender: RNIContentViewParentDelegate,
    childComponentView: UIView,
    index: NSInteger,
    superBlock: () -> Void
  ) {
    #if !RCT_NEW_ARCH_ENABLED
    superBlock();
    #endif
    
    childComponentView.removeFromSuperview();
  };
  
  public func notifyDidSetProps(sender: RNIContentViewParentDelegate) {
    self._setupIfNeeded();
  };

  public func notifyOnViewCommandRequest(
    sender: RNIContentViewParentDelegate,
    forCommandName commandName: String,
    withCommandArguments commandArguments: NSDictionary,
    resolve resolveBlock: @escaping RNIContentView.PromiseCompletionBlock,
    reject rejectBlock: @escaping RNIContentView.PromiseRejectionBlock
  ) {
    
    do {
      guard let commandArguments = commandArguments as? Dictionary<String, Any> else {
        throw RNIContextMenuError(
            errorCode: .invalidValue,
            description: "Unable to parse commandArguments",
            extraDebugValues: [
              "commandName": commandName,
              "commandArguments": commandArguments,
            ]
          );
      };
      
      switch commandName {
        case "presentMenu":
          try self.presentMenu();
          resolveBlock([:]);
          
        case "dismissMenu":
          try self.dismissMenu();
          resolveBlock([:]);
          
        case "provideDeferredElements":
          let id: String =
            try commandArguments.getValueFromDictionary(forKey: "id");
            
          let menuElementsRaw: [Any] =
            try commandArguments.getValueFromDictionary(forKey: "menuElements");
            
          let menuElements: [RNIMenuElement] = menuElementsRaw.compactMap {
            guard let dict = $0 as? Dictionary<String, Any> else {
              return nil;
            };
            
            return .init(dictionary: dict);
          };
          
          try self.provideDeferredElements(
            id: id,
            menuElements: menuElements
          );
          
          resolveBlock([:]);
          
        default:
          throw RNIContextMenuError(
            errorCode: .invalidValue,
            description: "No matching command for commandName",
            extraDebugValues: [
              "commandName": commandName,
              "commandArguments": commandArguments,
            ]
          );
      };
    
    } catch {
      rejectBlock(error.localizedDescription);
    };
  };
  
  // MARK: - Fabric Only
  // -------------------

  #if RCT_NEW_ARCH_ENABLED
  public func shouldRecycleContentDelegate(
    sender: RNIContentViewParentDelegate
  ) -> Bool {
    return false;
  };
  #endif
};


// MARK: - RNINavigationEventsNotifiable
// -------------------------------------

extension RNIContextMenuButtonContent: RNIMenuElementEventsNotifiable {

  public func notifyOnMenuElementUpdateRequest(for element: RNIMenuElement) {
    guard let menuConfig = self.menuConfig else { return };
    self.updateContextMenuIfVisible(with: menuConfig);
  };
};

// MARK: - RNINavigationEventsNotifiable
// -------------------------------------

extension RNIContextMenuButtonContent: RNINavigationEventsNotifiable {
  
  public func notifyViewControllerDidPop(
    sender: RNINavigationEventsReportingViewController
  ) {
    // TODO: WIP - To be re-impl.
    // try? self.viewCleanupMode
    //  .triggerCleanupIfNeededForViewControllerDidPopEvent(for: self);
  };
};
