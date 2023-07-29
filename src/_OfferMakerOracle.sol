// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// import { OfferMaker, IMangrove, AbstractRouter } from "mgv_src/strategies/offer_maker/OfferMaker.sol";
import { AggregatorV3Interface } from "./chainlink/AggregatorV3Interface.sol";

import {Direct, AbstractRouter, IMangrove, IERC20} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";



/**
 * @title OfferMakerOracle
 * @author Maxence Raballand
 * 
 * @notice 
 * This is an offer maker that uses Chainlink oracle to get the price of the token 
 * This potentially renege offer with a given slippage
 * 
 * This is not ILiquidityProvider compliant because we had the max slippage var to each lp
 */
contract OfferMakerOracle is Direct {

  uint public constant SLIPPAGE_PRECISION = 10000;
  uint public constant MAX_SLIPPAGE = SLIPPAGE_PRECISION * 100;

  mapping(uint => uint) public offerMaxSlippage;

  mapping(address => AggregatorV3Interface) internal _priceFeed;
  event PriceFeedUpdated(address token, address priceFeed);

  /// @param _initFeeds Two arrays of same length, one with tokens, one with price feeds
  constructor(IMangrove mgv, AbstractRouter router_, address deployer, uint gasreq, address owner, bytes memory _initFeeds)
  Direct(mgv, router_, gasreq, owner) {
    if (deployer != msg.sender) {
      setAdmin(deployer);
    }

    (address[] memory tokens, address[] memory feeds) = abi.decode(_initFeeds, (address[], address[]));
    _updatePriceFeeds(tokens, feeds);
  }

  /// Update the price feed of a token
  /// @param token Token to get the price of
  /// @param priceFeed_ Chainlink price feed address (only pair with USD are supported)
  function _updatePriceFeed(address token, address priceFeed_) internal {
    _priceFeed[token] = AggregatorV3Interface(priceFeed_);
    emit PriceFeedUpdated(token, priceFeed_);
  }

  function _updatePriceFeeds(address[] memory tokens, address[] memory priceFeeds) internal {
    require(tokens.length == priceFeeds.length, "OfferMakerOracle/setPriceFeed/mismatched-length");
    for (uint i = 0; i < tokens.length; i++) {
      _updatePriceFeed(tokens[i], priceFeeds[i]);
    }
  }

  function updatePriceFeed(address token, address priceFeed_) external onlyAdmin {
    _updatePriceFeed(token, priceFeed_);
  }

  function updatePriceFeeds(address[] calldata tokens, address[] calldata priceFeeds) external onlyAdmin {
    _updatePriceFeeds(tokens, priceFeeds);
  }

  /// This hook is called before creating an offer
  /// It checks if the price feed exisits for the outbound and inbound token
  function __before_offer__(address outbound_tkn, address inbound_tkn) internal view {
    require(address(_priceFeed[outbound_tkn]) != address(0), "OfferMakerOracle/offer/unknown-outbound-token");
    require(address(_priceFeed[inbound_tkn]) != address(0), "OfferMakerOracle/offer/unknown-inbound-token");
  }

  function _updateMaxSlippage(uint offerId, uint maxSlippage_) internal {
    require(maxSlippage_ <= MAX_SLIPPAGE, "OfferMakerOracle/offer/max-slippage-too-high");
    offerMaxSlippage[offerId] = maxSlippage_;
  }

  // ------------------
  // Offer creation
  // ------------------

  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint gasreq, uint maxSlippage, bytes memory newPools) 
    public
    payable
    onlyAdmin
    returns (uint offerId)
  {
    if(newPools.length > 0) {
      (address[] memory tokens, address[] memory feeds) = abi.decode(newPools, (address[], address[]));
      _updatePriceFeeds(tokens, feeds);
    }
    __before_offer__(address(outbound_tkn), address(inbound_tkn));
    (offerId,) = _newOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: gasreq,
        gasprice: 0,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false
      })
    );
    _updateMaxSlippage(offerId, maxSlippage);
  }

  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint gasreq, uint maxSlippage)
    public
    payable
    onlyAdmin
    returns (uint offerId)
  {
    return newOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, gasreq, maxSlippage, "");
  }

  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint maxSlippage, bytes memory newPools) 
    external
    payable
    onlyAdmin
    returns (uint offerId)
  {
    return newOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerGasreq(), maxSlippage, newPools);
  }

  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint maxSlippage)
    external
    payable
    onlyAdmin
    returns (uint offerId)
  {
    return newOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerGasreq(), maxSlippage);
  }

  function updateOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint pivotId,
    uint offerId,
    uint gasreq,
    uint maxSlippage
  ) public payable onlyAdmin {
    _updateOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: gasreq,
        gasprice: 0,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false
      }),
      offerId
    );
    _updateMaxSlippage(offerId, maxSlippage);
  }

  function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId, uint maxSlippage)
    external
    payable
    onlyAdmin
  {
    updateOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerId, offerGasreq(), maxSlippage);
  }

  function retractOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, bool deprovision)
    public
    adminOrCaller(address(MGV))
    returns (uint freeWei)
  {
    freeWei = _retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
    if (freeWei > 0) {
      require(MGV.withdraw(freeWei), "Direct/withdrawFail");
      (bool noRevert,) = admin().call{value: freeWei}("");
      require(noRevert, "mgvOffer/weiTransferFail");
    }
  }

  function _getPriceData(address token) internal view returns (uint price, uint decimals) {
    (,int price_,,,) = _priceFeed[token].latestRoundData();
    price = uint(price_);
    decimals = _priceFeed[token].decimals();
  }

  function _price(uint sellingAssetPrice, uint buyingAssetPrice, uint sellingAssetDec, uint buyingAssetDec) internal pure returns (uint price) {
    if(sellingAssetDec > buyingAssetDec) {
      price = sellingAssetPrice / (buyingAssetPrice * 10 ** (sellingAssetDec - buyingAssetDec));
    } else if(sellingAssetDec < buyingAssetDec) {
      price = (sellingAssetPrice * 10 ** (buyingAssetDec - sellingAssetDec)) / buyingAssetPrice;
    } else {
      price = sellingAssetPrice / buyingAssetPrice;
    }
  }

  function _getSlippage(MgvLib.SingleOrder calldata order) internal view returns (uint slippage) {
    (uint priceOut, uint priceDecimalsOut) = _getPriceData(order.outbound_tkn);
    (uint priceIn, uint priceDecimalsIn) = _getPriceData(order.inbound_tkn);
    uint expected = _price(priceOut, priceIn, priceDecimalsOut, priceDecimalsIn);

    uint outboundDec = IERC20(order.outbound_tkn).decimals();
    uint inboundDec = IERC20(order.inbound_tkn).decimals();

    uint orderPrice = _price(order.gives, order.wants, outboundDec, inboundDec);

    if(orderPrice > expected) {
      slippage = (orderPrice - expected) * SLIPPAGE_PRECISION / orderPrice;
    } else {
      slippage = (expected - orderPrice) * SLIPPAGE_PRECISION / expected;
    }
  }

  function __lastLook__(MgvLib.SingleOrder calldata order) internal virtual override returns (bytes32 data) {
    uint offerId = order.offerId;
    uint maxSlippage = offerMaxSlippage[offerId];
    uint slippage = _getSlippage(order);
    require(slippage <= maxSlippage, "OfferMakerOracle/slippage-too-high");
    data = super.__lastLook__(order);
  }
}