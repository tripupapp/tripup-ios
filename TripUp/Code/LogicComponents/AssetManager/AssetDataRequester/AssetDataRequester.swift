//
//  DataRequester.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 18/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation

protocol AssetDataRequester: AssetImageRequester, AssetAVRequester {}

extension AssetManager: AssetDataRequester {}
