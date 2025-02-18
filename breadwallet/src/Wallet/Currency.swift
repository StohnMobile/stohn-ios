//
//  Currency.swift
//  breadwallet
//
//  Created by Ehsan Rezaie on 2018-01-10.
//  Copyright © 2018-2019 Breadwinner AG. All rights reserved.
//

import Foundation
import WalletKit
import UIKit
import CoinGecko

protocol CurrencyWithIcon {
    var code: String { get }
    var colors: (UIColor, UIColor) { get }
}

typealias CurrencyUnit = WalletKit.Unit
typealias CurrencyId = Identifier<Currency>

/// Combination of the Core Currency model and its metadata properties
class Currency: CurrencyWithIcon {
    public enum TokenType: String {
        case native
        case erc20
        case unknown
    }

    private let core: WalletKit.Currency
    let network: WalletKit.Network

    /// Unique identifier from BlockchainDB
    var uid: CurrencyId { assert(core.uid == metaData.uid); return metaData.uid }
    /// Ticker code (e.g. BTC)
    var code: String { return core.code.uppercased() }
    /// Display name (e.g. Bitcoin)
    var name: String { return metaData.name }

    var cryptoCompareCode: String {
        return metaData.alternateCode?.uppercased() ?? core.code.uppercased()
    }
    
    var coinGeckoId: String? {
        return metaData.coinGeckoId
    }
    
    // Number of confirmations needed until a transaction is considered complete
    // eg. For bitcoin, a txn is considered complete when it has 6 confirmations
    var confirmationsUntilFinal: Int {
        return Int(network.confirmationsUntilFinal)
    }
    
    var tokenType: TokenType {
        guard let type = TokenType(rawValue: core.type.lowercased()) else { assertionFailure("unknown token type"); return .unknown }
        return type
    }
    
    // MARK: Units

    /// The smallest divisible unit (e.g. satoshi)
    let baseUnit: CurrencyUnit
    /// The default unit used for fiat exchange rate and amount display (e.g. bitcoin)
    let defaultUnit: CurrencyUnit
    /// All available units for this currency by name
    private let units: [String: CurrencyUnit]
    
    var defaultUnitName: String {
        return name(forUnit: defaultUnit)
    }

    /// Returns the unit associated with the number of decimals if available
    func unit(forDecimals decimals: Int) -> CurrencyUnit? {
        return units.values.first { $0.decimals == decimals }
    }

    func unit(named name: String) -> CurrencyUnit? {
        return units[name.lowercased()]
    }

    func name(forUnit unit: CurrencyUnit) -> String {
        if unit.decimals == defaultUnit.decimals {
            return code.uppercased()
        } else {
            return unit.name
        }
    }

    func unitName(forDecimals decimals: UInt8) -> String {
        return unitName(forDecimals: Int(decimals))
    }

    func unitName(forDecimals decimals: Int) -> String {
        guard let unit = unit(forDecimals: decimals) else { return "" }
        return name(forUnit: unit)
    }

    // MARK: Metadata

    let metaData: CurrencyMetaData

    /// Primary + secondary color
    var colors: (UIColor, UIColor) { return metaData.colors }
    /// False if a token has been delisted, true otherwise
    var isSupported: Bool { return metaData.isSupported }
    var tokenAddress: String? { return metaData.tokenAddress }
    
    // MARK: URI

    var urlSchemes: [String]? {
        if isBitcoin {
            return ["bitcoin"]
        }
        return nil
    }
    
    func doesMatchPayId(_ details: PayIdAddress) -> Bool {
        let environment = (E.isTestnet || E.isRunningTests) ? "testnet" : "mainnet"
        guard details.environment.lowercased() == environment else { return false }
        guard let id = payId else { return false }
        return details.paymentNetwork.lowercased() == id.lowercased()
    }
    
    var payId: String? {
        if isBitcoin { return "btc" }
        return nil
    }
    
    var attributeDefinition: AttributeDefinition? {
        return nil
    }
    
    /// Can be used if an example address is required eg. to estimate the max send limit
    var placeHolderAddress: String? {
        if isBitcoin {
            return E.isTestnet ? "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx" : "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        }
        return nil
    }

    /// Returns a transfer URI with the given address
    func addressURI(_ address: String) -> String? {
        guard let scheme = urlSchemes?.first, isValidAddress(address) else { return nil }
        return "\(scheme):\(address)"
    }
    
    func shouldAcceptQRCodeFrom(_ currency: Currency, request: PaymentRequest) -> Bool {
        if self == currency {
            return true
        }
        
        return false
    }
    
    // MARK: Init

    init?(core: WalletKit.Currency,
          network: WalletKit.Network,
          metaData: CurrencyMetaData,
          units: Set<WalletKit.Unit>,
          baseUnit: WalletKit.Unit,
          defaultUnit: WalletKit.Unit) {
        guard core.uid == metaData.uid else { return nil }
        self.core = core
        self.network = network
        self.metaData = metaData
        self.units = Array(units).reduce([String: CurrencyUnit]()) { (dict, unit) -> [String: CurrencyUnit] in
            var dict = dict
            dict[unit.name.lowercased()] = unit
            return dict
        }
        self.baseUnit = baseUnit
        self.defaultUnit = defaultUnit
    }
}

extension Currency: Hashable {
    static func == (lhs: Currency, rhs: Currency) -> Bool {
        return lhs.core == rhs.core && lhs.metaData == rhs.metaData
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(core)
        hasher.combine(metaData)
    }
}

// MARK: - Convenience Accessors

extension Currency {
    
    func isValidAddress(_ address: String) -> Bool {
        return Address.create(string: address, network: network) != nil
    }

    /// Ticker code for support pages
    var supportCode: String {
        if tokenType == .erc20 {
            return "erc20"
        } else {
            return code.lowercased()
        }
    }

    var isBitcoin: Bool { return uid == Currencies.btc.uid }
    var isBitcoinCompatible: Bool { return isBitcoin }
}

// MARK: - Confirmation times

extension Currency {
    func feeText(forIndex index: Int) -> String {
        if isBitcoinCompatible {
            return btcFeeText(forIndex: index)
        } else {
            return String(format: S.Confirmation.processingTime, S.FeeSelector.ethTime)
        }
    }
    
    private func ethFeeText(forIndex index: Int) -> String {
        
        switch index {
        case 0:
            return String(format: S.FeeSelector.estimatedDelivery, timeString(forMinutes: 6))
        case 1:
            return String(format: S.FeeSelector.estimatedDelivery, timeString(forMinutes: 4))
        case 2:
            return String(format: S.FeeSelector.estimatedDelivery, timeString(forMinutes: 2))
        default:
            return ""
        }
    }
    
    private func timeString(forMinutes minutes: Int) -> String {
        let duration: TimeInterval = Double(minutes * 60)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .brief
        formatter.allowedUnits = [.minute]
        formatter.zeroFormattingBehavior = [.dropLeading]
        return formatter.string(from: duration) ?? ""
    }
    
    private func btcFeeText(forIndex index: Int) -> String {
        switch index {
        case 0:
            return String(format: S.FeeSelector.estimatedDelivery, S.FeeSelector.economyTime)
        case 1:
            return String(format: S.FeeSelector.estimatedDelivery, S.FeeSelector.regularTime)
        case 2:
            return String(format: S.FeeSelector.estimatedDelivery, S.FeeSelector.priorityTime)
        default:
            return ""
        }
    }
}

// MARK: - Images

extension CurrencyWithIcon {
    /// Icon image with square color background
    public var imageSquareBackground: UIImage? {
        if let baseURL = AssetArchive(name: imageBundleName, apiClient: Backend.apiClient)?.extractedUrl {
            let path = baseURL.appendingPathComponent("white-square-bg").appendingPathComponent(code.lowercased()).appendingPathExtension("png")
            if let data = try? Data(contentsOf: path) {
                return UIImage(data: data)
            }
        }
        return TokenImageSquareBackground(code: code, color: colors.0).renderedImage
    }

    /// Icon image with no background using template rendering mode
    public var imageNoBackground: UIImage? {
        if let baseURL = AssetArchive(name: imageBundleName, apiClient: Backend.apiClient)?.extractedUrl {
            let path = baseURL.appendingPathComponent("white-no-bg").appendingPathComponent(code.lowercased()).appendingPathExtension("png")
            if let data = try? Data(contentsOf: path) {
                return UIImage(data: data)?.withRenderingMode(.alwaysTemplate)
            }
        }
        
        return TokenImageNoBackground(code: code, color: colors.0).renderedImage
    }
    
    private var imageBundleName: String {
        return (E.isDebug || E.isTestFlight) ? "brd-tokens-staging" : "brd-tokens"
    }
}

// MARK: - Metadata Model

/// Model representing metadata for supported currencies
public struct CurrencyMetaData: CurrencyWithIcon {
    
    let uid: CurrencyId
    let code: String
    let isSupported: Bool
    let colors: (UIColor, UIColor)
    let name: String
    var tokenAddress: String?
    var decimals: UInt8
    
    var isPreferred: Bool {
        return Currencies.allCases.map { $0.uid }.contains(uid)
    }

    /// token type string in format expected by System.asBlockChainDBModelCurrency
    var type: String {
        return uid.rawValue.contains("__native__") ? "NATIVE" : "ERC20"
    }

    var alternateCode: String?
    var coinGeckoId: String?
    
    enum CodingKeys: String, CodingKey {
        case uid = "currency_id"
        case code
        case isSupported = "is_supported"
        case colors
        case tokenAddress = "contract_address"
        case name
        case decimals = "scale"
        case alternateNames = "alternate_names"
    }
}

extension CurrencyMetaData: Codable {
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        //TODO:CRYPTO temp hack until testnet support to added /currencies endpoint (BAK-318)
        var uid = try container.decode(String.self, forKey: .uid)
        if E.isTestnet {
            uid = uid.replacingOccurrences(of: "mainnet", with: "testnet")
            uid = uid.replacingOccurrences(of: "0x558ec3152e2eb2174905cd19aea4e34a23de9ad6", with: "0x7108ca7c4718efa810457f228305c9c71390931a") // BRD token
            uid = uid.replacingOccurrences(of: "ethereum-testnet", with: "ethereum-ropsten")
        }
        self.uid = CurrencyId(rawValue: uid) //try container.decode(CurrencyId.self, forKey: .uid)
        code = try container.decode(String.self, forKey: .code)
        let colorValues = try container.decode([String].self, forKey: .colors)
        if colorValues.count == 2 {
            colors = (UIColor.fromHex(colorValues[0]), UIColor.fromHex(colorValues[1]))
        } else {
            if E.isDebug {
                throw DecodingError.dataCorruptedError(forKey: .colors, in: container, debugDescription: "Invalid/missing color values")
            }
            colors = (UIColor.black, UIColor.black)
        }
        isSupported = try container.decode(Bool.self, forKey: .isSupported)
        name = try container.decode(String.self, forKey: .name)
        tokenAddress = try container.decode(String.self, forKey: .tokenAddress)
        decimals = try container.decode(UInt8.self, forKey: .decimals)
        
        var didFindCoinGeckoID = false
        if let alternateNames = try? container.decode([String: String].self, forKey: .alternateNames) {
            if let code = alternateNames["cryptocompare"] {
                alternateCode = code
            }
            
            if let id = alternateNames["coingecko"] {
                didFindCoinGeckoID = true
                coinGeckoId = id
            }
        }
        
        // If the /currencies endpoint hasn't provided a coingeckoID,
        // use the local list. Eventually /currencies should provide
        // all of them
        if !didFindCoinGeckoID {
            if let id = CoinGeckoCodes.map[code.uppercased()] {
                coinGeckoId = id
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uid, forKey: .uid)
        try container.encode(code, forKey: .code)
        var colorValues = [String]()
        colorValues.append(colors.0.toHex)
        colorValues.append(colors.1.toHex)
        try container.encode(colorValues, forKey: .colors)
        try container.encode(isSupported, forKey: .isSupported)
        try container.encode(name, forKey: .name)
        try container.encode(tokenAddress, forKey: .tokenAddress)
        try container.encode(decimals, forKey: .decimals)
        
        var alternateNames = [String: String]()
        if let alternateCode = alternateCode {
            alternateNames["cryptocompare"] = alternateCode
        }
        if let coingeckoId = coinGeckoId {
            alternateNames["coingecko"] = coingeckoId
        }
        if !alternateNames.isEmpty {
            try container.encode(alternateNames, forKey: .alternateNames)
        }
    }
}

extension CurrencyMetaData: Hashable {
    public static func == (lhs: CurrencyMetaData, rhs: CurrencyMetaData) -> Bool {
        return lhs.uid == rhs.uid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}

/// Natively supported currencies. Enum maps to ticker code.
enum Currencies: String, CaseIterable {
    case btc
    
    var code: String { return rawValue }
    var uid: CurrencyId {
        var uids = ""
        switch self {
        case .btc:
            uids = "bitcoin-\(E.isTestnet ? "testnet" : "mainnet"):__native__"
        }
        return CurrencyId(rawValue: uids)
    }
    
    var state: WalletState? { return Store.state.wallets[uid] }
    var wallet: Wallet? { return state?.wallet }
    var instance: Currency? { return state?.currency }
}

extension WalletKit.Currency {
    var uid: CurrencyId { return CurrencyId(rawValue: uids) }
}

struct AttributeDefinition {
    let key: String
    let label: String
    let keyboardType: UIKeyboardType
    let maxLength: Int
}
