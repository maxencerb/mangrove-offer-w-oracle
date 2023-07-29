// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { AggregatorV3Interface } from "./chainlink/AggregatorV3Interface.sol";

import {Direct, AbstractRouter, IMangrove, MangroveOffer, IERC20} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";

abstract contract DirectOracle is Direct {

  struct Slippage {
    uint128 maxSlippage;
    // if true, doesn't allow for any slippage (even prositive)
    bool strict;
    // keep order if failed
    bool keepOrder;
    // deprovision if don't keep order
    bool deprovision;
  }

  uint public constant SLIPPAGE_PRECISION = 1e6;
  uint public constant MAX_SLIPPAGE = SLIPPAGE_PRECISION * 100;

  uint public constant PRICE_PRECISION = 1e8;

  mapping(address => AggregatorV3Interface) internal _priceFeed;

  event PriceFeedUpdated(address token, address priceFeed);
  event RetractedSlippageIncompatibleOffer(address indexed outbound_tkn, address indexed inbound_tkn, uint indexed offerId);
  event UpdatedOfferMaxSlippage(address indexed outbound_tkn, address indexed inbound_tkn, uint indexed offerId, Slippage slippage);

  constructor(IMangrove mgv, AbstractRouter router_, uint gasreq, address owner)
  Direct(mgv, router_, gasreq, owner) {}

  modifier checkSlippage(Slippage memory slippage) {
    require(slippage.maxSlippage <= MAX_SLIPPAGE, "DirectOracle/max-slippage-too-high");
    _;
  }

  function getOfferMaxSlippageStorage(address outbound, address inbound, uint offerId) internal pure returns (Slippage storage slippage) {
    bytes32 position = keccak256(abi.encodePacked(outbound, inbound, offerId));
    assembly {
      slippage.slot := position
    }
  }


  /// Update the price feed of a token
  /// @param token Token to get the price of
  /// @param priceFeed_ Chainlink price feed address (only pair with USD are supported)
  function _updatePriceFeed(address token, address priceFeed_) internal {
    _priceFeed[token] = AggregatorV3Interface(priceFeed_);
    emit PriceFeedUpdated(token, priceFeed_);
  }

  function _updatePriceFeeds(address[] memory tokens, address[] memory priceFeeds) internal {
    require(tokens.length == priceFeeds.length, "DirectOracle/mismatched-length");
    for (uint i = 0; i < tokens.length; i++) {
      _updatePriceFeed(tokens[i], priceFeeds[i]);
    }
  }

  /// 
  /// @param asset The asset to price
  /// @return price price of the asset from the oracle
  /// @return decimals number of decimals for price precision
  function _getPrice(address asset) internal view returns (uint price, uint decimals) {
    AggregatorV3Interface priceFeed = _priceFeed[asset];
    require(address(priceFeed) != address(0), "DirectOracle/price-feed-not-found");
    (, int price_, , , ) = priceFeed.latestRoundData();
    price = uint(price_);
    decimals = priceFeed.decimals();
  }

  function _priceOf(uint asset1, uint asset2, uint dec1, uint dec2) internal pure returns (uint price) {
    if (dec1 > dec2) {
      price = asset1 * PRICE_PRECISION / asset2 * (10 ** (dec1 - dec2));
    } else {
      price = asset1 * PRICE_PRECISION * (10 ** (dec2 - dec1)) / asset2;
    }
  }

  function _slippage(uint gives, uint wants, address outbond, address inbound) internal view returns (uint slippage, bool upper) {
    (uint price1, uint dec1) = _getPrice(outbond);
    (uint price2, uint dec2) = _getPrice(inbound);
    // Compute the price of the asset we are selling compared to the asset we are buying
    uint price = _priceOf(price1, price2, dec1, dec2);

    // Get the assets decimals
    dec1 = IERC20(outbond).decimals();
    dec2 = IERC20(inbound).decimals();

    // Compute the price given the offer
    uint offerPrice = _priceOf(gives, wants, dec1, dec2);

    // compare
    upper = offerPrice >= price;

    if (upper) {
      slippage = (offerPrice - price) * SLIPPAGE_PRECISION / price;
    } else {
      slippage = (price - offerPrice) * SLIPPAGE_PRECISION / price;
    }
  }

  function _newOffer(OfferArgs memory args, Slippage memory slippage) 
    internal
    checkSlippage(slippage)
    returns (uint offerId, bytes32 status) 
  {
    require(address(_priceFeed[address(args.outbound_tkn)]) != address(0), "DirectOracle/price-feed-not-found");
    require(address(_priceFeed[address(args.inbound_tkn)]) != address(0), "DirectOracle/price-feed-not-found");
    (offerId, status) = _newOffer(args);
    Slippage storage maxSlippage = getOfferMaxSlippageStorage(address(args.outbound_tkn), address(args.inbound_tkn), offerId);
    maxSlippage.maxSlippage = slippage.maxSlippage;
    maxSlippage.strict = slippage.strict;
    maxSlippage.keepOrder = slippage.keepOrder;
    emit UpdatedOfferMaxSlippage(address(args.outbound_tkn), address(args.inbound_tkn), offerId, slippage);
  }

  function _updateOffer(OfferArgs memory args, uint offerId, Slippage memory slippage) 
    internal
    checkSlippage(slippage)
    returns (bytes32 status) 
  {
    status = _updateOffer(args, offerId);
    Slippage storage maxSlippage = getOfferMaxSlippageStorage(address(args.outbound_tkn), address(args.inbound_tkn), offerId);
    maxSlippage.maxSlippage = slippage.maxSlippage;
    maxSlippage.strict = slippage.strict;
    maxSlippage.keepOrder = slippage.keepOrder;
    emit UpdatedOfferMaxSlippage(address(args.outbound_tkn), address(args.inbound_tkn), offerId, slippage);
  }

  function _isSlippageAcceptable(uint gives, uint wants, address outbound, address inbound, uint offerId) internal view returns (bool) {
    (uint slippage, bool upper) = _slippage(gives, wants, outbound, inbound);
    Slippage storage maxSlippage = getOfferMaxSlippageStorage(outbound, inbound, offerId);
    return slippage <= maxSlippage.maxSlippage || (!maxSlippage.strict && upper);
  }

  /// @inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal virtual override returns (bytes32 data) {
    require(_isSlippageAcceptable(order.gives, order.wants, order.outbound_tkn, order.inbound_tkn, order.offerId), "DirectOracle/slippage-too-high");
    data = super.__lastLook__(order);
  }

  /// @inheritdoc MangroveOffer
  function __posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result)
    internal
    virtual
    override
    returns (bytes32 data)
  {
    Slippage storage maxSlippage = getOfferMaxSlippageStorage(order.outbound_tkn, order.inbound_tkn, order.offerId);
    if (
      !maxSlippage.keepOrder &&
      !_isSlippageAcceptable(order.gives, order.wants, order.outbound_tkn, order.inbound_tkn, order.offerId)
    ) {
      // retract offer if slippage is still too high
      _retractOffer(IERC20(order.outbound_tkn), IERC20(order.inbound_tkn), order.offerId, maxSlippage.deprovision);
      emit RetractedSlippageIncompatibleOffer(order.outbound_tkn, order.inbound_tkn, order.offerId);
    }
    data = super.__posthookFallback__(order, result);
  }
}