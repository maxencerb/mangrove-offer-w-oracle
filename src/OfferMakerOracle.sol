// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { DirectOracle, IMangrove, AbstractRouter, IERC20 } from './DirectOracle.sol';

contract OfferMakerOracle is DirectOracle {


  constructor(IMangrove mgv, address owner, bytes memory _initFeeds)
  DirectOracle(mgv, NO_ROUTER, 100_000, owner) {
    if (owner != msg.sender) {
      setAdmin(owner);
    }

    if (_initFeeds.length > 0) {
      (address[] memory tokens, address[] memory feeds) = abi.decode(_initFeeds, (address[], address[]));
      _updatePriceFeeds(tokens, feeds);
    }
    
  }

  function updatePriceFeeds(address[] memory tokens, address[] memory priceFeeds) external onlyAdmin {
    require(tokens.length == priceFeeds.length, "OfferMakerOracle/setPriceFeed/mismatched-length");
    for (uint i = 0; i < tokens.length; i++) {
      _updatePriceFeed(tokens[i], priceFeeds[i]);
    }
  }

  function updatePriceFeed(address token, address priceFeed_) external onlyAdmin {
    _updatePriceFeed(token, priceFeed_);
  }

  // Create offer

  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, Slippage memory slippage, uint gasreq, bytes memory newPools) 
    public
    payable
    onlyAdmin
    returns (uint offerId)
  {
    if(newPools.length > 0) {
      (address[] memory tokens, address[] memory feeds) = abi.decode(newPools, (address[], address[]));
      _updatePriceFeeds(tokens, feeds);
    }
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
      }),
      slippage
    );
  }

  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, Slippage memory slippage, bytes memory newPools) 
    public
    payable
    onlyAdmin
    returns (uint offerId)
  {
    return newOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, slippage, offerGasreq(), newPools);
  }

  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, Slippage memory slippage)
    external
    payable
    onlyAdmin
    returns (uint offerId)
  {
    return newOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, slippage, offerGasreq(), "");
  }

  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, Slippage memory slippage, uint gasreq)
    external
    payable
    onlyAdmin
    returns (uint offerId)
  {
    return newOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, slippage, gasreq, "");
  }

  // update offer
  function updateOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint pivotId,
    uint offerId,
    uint gasreq,
    Slippage memory slippage
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
      offerId,
      slippage
    );
  }

  function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId, Slippage memory slippage)
    external
    payable
    onlyAdmin
  {
    updateOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerId, offerGasreq(), slippage);
  }

  // update offer and not slippage

  function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId, uint gasreq)
    external
    payable
    onlyAdmin
  {
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
  }

  function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId)
    external
    payable
    onlyAdmin
  {
    _updateOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: offerGasreq(),
        gasprice: 0,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false
      }),
      offerId
    );
  }

  // Retract offer

  function retractOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, bool deprovision)
    public
    override
    adminOrCaller(address(MGV))
    returns (uint freeWei)
  {
    freeWei = super.retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
    if (freeWei > 0) {
      require(MGV.withdraw(freeWei), "Direct/withdrawFail");
      (bool noRevert,) = admin().call{value: freeWei}("");
      require(noRevert, "mgvOffer/weiTransferFail");
    }
  }

  function offerSlippage(address outbound_tkn, address inbound_tkn, uint offerId) external view returns (Slippage memory) {
    return offerMaxSlippage[outbound_tkn][inbound_tkn][offerId];
  }
}