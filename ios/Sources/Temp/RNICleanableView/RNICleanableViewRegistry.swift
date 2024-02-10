//
//  RNICleanableViewRegistry.swift
//  ReactNativeIosContextMenu
//
//  Created by Dominic Go on 2/10/24.
//

import UIKit
import React
import ExpoModulesCore
import DGSwiftUtilities
import ReactNativeIosUtilities


public let RNICleanableViewRegistryShared = RNICleanableViewRegistry.shared;

public class RNICleanableViewRegistry {

  public static var debugShouldLogCleanup = false;
  public static var debugShouldLogRegister = false;

  public static let shared: RNICleanableViewRegistry = .init();
  
  // MARK: - Properties
  // ------------------
  
  public var registry: Dictionary<Int, RNICleanableViewItem> = [:];
  
  weak var _bridge: RCTBridge?;
  
  // MARK: - Functions
  // -----------------
  
  init(){
    // no-op
  };
  
  public func register(
    forDelegate entry: RNICleanableViewDelegate,
    initialViewsToCleanup initialViewsToCleanupRaw: [UIView] = [],
    shouldIncludeDelegateInViewsToCleanup: Bool = true,
    shouldProceedCleanupWhenDelegateIsNil: Bool = true
  ){
    
    self._setBridgeIfNeeded(usingDelegate: entry);
    
    var initialViewsToCleanup = initialViewsToCleanupRaw.map {
      WeakRef(with: $0);
    };
    
    if shouldIncludeDelegateInViewsToCleanup,
       let reactView = entry as? RCTView {
       
      initialViewsToCleanup.append(
        .init(with: reactView)
      );
    };
    
    #if DEBUG
    if Self.debugShouldLogRegister {
      print(
        "RNICleanableViewRegistry.register",
        "\n - delegate.viewCleanupKey:", entry.viewCleanupKey,
        "\n - delegate type:", type(of: entry),
        "\n - initialViewsToCleanup.count", initialViewsToCleanup.count,
        "\n - shouldIncludeDelegateInViewsToCleanup", shouldIncludeDelegateInViewsToCleanup,
        "\n - shouldProceedCleanupWhenDelegateIsNil", shouldProceedCleanupWhenDelegateIsNil,
        "\n"
      );
    };
    #endif
    
  
    self.registry[entry.viewCleanupKey] = .init(
      key: entry.viewCleanupKey,
      delegate: entry,
      viewsToCleanup: initialViewsToCleanup,
      shouldProceedCleanupWhenDelegateIsNil: shouldProceedCleanupWhenDelegateIsNil
    );
  };
  
  // TOOD: Mark as throws - Add error throwing
  func unregister(forDelegate delegate: RNICleanableViewDelegate){
    guard let match = self.getEntry(forKey: delegate.viewCleanupKey)
    else { return };
    
    self.registry.removeValue(forKey: match.key);
  };
  
  public func getEntry(forKey key: Int) -> RNICleanableViewItem? {
    return self.registry[key];
  };
  
  // TOOD: Mark as throws - Add error throwing
  public func notifyCleanup(
    forKey key: Int,
    sender: RNICleanableViewSenderType
  ) throws {
    guard let match = self.getEntry(forKey: key) else { return };
    
    var shouldCleanup = false;
    
    if let delegate = match.delegate {
      shouldCleanup = delegate.notifyOnViewCleanupRequest(
        sender: sender,
        item: match
      );
    
    } else if match.shouldProceedCleanupWhenDelegateIsNil {
      shouldCleanup = true;
    };
    
    guard shouldCleanup else { return };
    
    var viewsToCleanup: [UIView] = [];
    var cleanableViewDelegates: [RNICleanableViewDelegate] = [];
    
    for weakView in match.viewsToCleanup {
      guard let view = weakView.ref else { continue };
      
      let isDuplicate = viewsToCleanup.contains {
        view.tag == $0.tag;
      };
      
      guard !isDuplicate else { continue };
      
      switch view {
        case let cleanableView as RNICleanableViewDelegate:
          guard cleanableView !== match.delegate else { fallthrough };
          cleanableViewDelegates.append(cleanableView);
          
        default:
          viewsToCleanup.append(view)
      };
    };
    
    let cleanableViewItems = cleanableViewDelegates.compactMap {
      self.getEntry(forKey: $0.viewCleanupKey);
    };
    
    try self._cleanup(views: viewsToCleanup);
    
    match.delegate?.notifyOnViewCleanupCompletion();
    self.registry.removeValue(forKey: match.key);
    
    var failedToCleanupItems: [RNICleanableViewItem] = [];
    cleanableViewItems.forEach {
      do {
        try self.notifyCleanup(
          forKey: $0.key,
          sender: sender
        );
        
      } catch {
        failedToCleanupItems.append($0);
      };
    };
    
    cleanableViewItems.forEach {
      #if DEBUG
      if Self.debugShouldLogCleanup {
        print(
          "RNICleanableViewRegistry - Failed to cleanup",
          "\n - key:", $0.key,
          "\n - type:", type(of: $0.delegate),
          "\n - shouldProceedCleanupWhenDelegateIsNil:", $0.shouldProceedCleanupWhenDelegateIsNil,
          "\n - viewsToCleanup.count", $0.viewsToCleanup.count,
          "\n"
        );
      };
      #endif
      
      // re-add failed items
      self.registry[$0.key] = $0;
    };
    
    #if DEBUG
    print(
      "RNICleanableViewRegistry.notifyCleanup",
      "\n - forKey:", key,
      "\n - match.viewsToCleanup.count:", match.viewsToCleanup.count,
      "\n - match.shouldProceedCleanupWhenDelegateIsNil:", match.shouldProceedCleanupWhenDelegateIsNil,
      "\n - viewsToCleanup.count:", viewsToCleanup.count,
      "\n - cleanableViewItems.count:", cleanableViewItems.count,
      "\n"
    );
    #endif
  };
  
  // MARK: - Internal Functions
  // --------------------------
  
  func _setBridgeIfNeeded(usingDelegate delegate: RNICleanableViewDelegate){
    guard self._bridge == nil else { return };
    
    // var window: UIWindow?;
    
    switch delegate {
      case let expoView as ExpoView:
        self._bridge = expoView.appContext?.reactBridge;
       // window = expoView.window;
        
      case let reactView as RCTView:
        self._bridge = reactView.closestParentRootView?.bridge;
        // window = reactView.window;
        
      // case let view as UIView:
      //   window = view.window;
        
      default:
        break;
    };
    
    // bridge is still nil, continue getting the bridge via other means...
    guard self._bridge == nil else { return };
    self._bridge = RNIHelpers.bridge;
  };
  
  func _cleanup(views viewsToCleanup: [UIView]) throws {
    guard let bridge = self._bridge else {
      // TODO: WIP - Replace
      throw NSError();
    };
    
    viewsToCleanup.forEach {
      RNIHelpers.recursivelyRemoveFromViewRegistry(
        forReactView: $0,
        usingReactBridge: bridge
      );
    };
    
    #if DEBUG
    if Self.debugShouldLogCleanup {
      let _viewsToCleanupTags = viewsToCleanup.map { $0.reactTag ?? -1 };
      print(
        "RNICleanableViewRegistry._cleanup",
        "\n - viewsToCleanup.count:", _viewsToCleanupTags.count,
        "\n - viewsToCleanup:", _viewsToCleanupTags,
        "\n"
      );
    };
    #endif
  };
};
