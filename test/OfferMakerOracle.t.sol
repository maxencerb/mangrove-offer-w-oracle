// SPDX-License-Identifier:	MIT
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/forks/Polygon.sol";

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";

import {AggregatorV3Interface} from "oracle_maker/chainlink/AggregatorV3Interface.sol";
import "oracle_maker/OfferMakerOracle.sol";

import {console} from "forge-std/console.sol";

contract OfferMakerOracleTest is MangroveTest {
  
  IERC20 weth;
  IERC20 dai;
  IERC20 usdc;

  AggregatorV3Interface eth_usd;
  AggregatorV3Interface dai_usd;
  AggregatorV3Interface usdc_usd;

  PolygonFork fork;

  address payable taker;
  OfferMakerOracle strat;

  uint constant PRICE_PRECISION = 1e8;

  receive() external payable virtual {}

  function setUp() public override {
    fork = new PolygonFork();

    fork = new PinnedPolygonFork(); // use polygon fork to use dai, usdc and weth addresses
    fork.setUp();

    // use convenience helpers to setup Mangrove
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));

    // setup tokens, markets and approve them
    dai = IERC20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
    weth = IERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
    usdc = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    // some price feeds
    eth_usd = AggregatorV3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945);
    dai_usd = AggregatorV3Interface(0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D);
    usdc_usd = AggregatorV3Interface(0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7); 

    setupMarket(dai, weth);
    setupMarket(usdc, weth);

    // setup separate taker and give some native token (for gas) + USDC and DAI
    taker = freshAddress("taker");
    deal(taker, 10_000_000);

    deal($(usdc), taker, cash(usdc, 10_000));
    deal($(dai), taker, cash(dai, 10_000));

    // approve DAI and USDC on Mangrove for taker
    vm.startPrank(taker);
    dai.approve($(mgv), type(uint).max);
    usdc.approve($(mgv), type(uint).max);
    vm.stopPrank();
  }

  function deployStratTest() public {
    strat = new OfferMakerOracle({
      mgv: IMangrove($(mgv)),
      owner: $(this),
      _initFeeds: ""
    });

    IERC20[] memory tokens = new IERC20[](3);
    tokens[0] = dai;
    tokens[1] = usdc;
    tokens[2] = weth;

    vm.expectRevert("DirectOracle/price-feed-not-found");
    strat.checkList(tokens);

    address[] memory tokens_ = new address[](3);
    tokens_[0] = address(dai);
    tokens_[1] = address(usdc);
    tokens_[2] = address(weth);

    // add price feeds
    address[] memory feeds = new address[](3);
    feeds[0] = address(dai_usd);
    feeds[1] = address(usdc_usd);
    feeds[2] = address(eth_usd);

    strat.updatePriceFeeds(tokens_, feeds);

    vm.expectRevert("mgvOffer/LogicMustApproveMangrove");
    strat.checkList(tokens);

    // and now activate them
    strat.activate(tokens);

    // and now check again
    strat.checkList(tokens);
  }

  function deployStrat() public {
    address[] memory tokens_ = new address[](3);
    tokens_[0] = address(dai);
    tokens_[1] = address(usdc);
    tokens_[2] = address(weth);

    address[] memory feeds = new address[](3);
    feeds[0] = address(dai_usd);
    feeds[1] = address(usdc_usd);
    feeds[2] = address(eth_usd);

    bytes memory initFeeds = abi.encode(tokens_, feeds);

    strat = new OfferMakerOracle({
      mgv: IMangrove($(mgv)),
      owner: $(this),
      _initFeeds: initFeeds
    });

    IERC20[] memory tokens = new IERC20[](3);
    tokens[0] = dai;
    tokens[1] = usdc;
    tokens[2] = weth;

    vm.expectRevert("mgvOffer/LogicMustApproveMangrove");
    strat.checkList(tokens);

    // and now activate them
    strat.activate(tokens);

    // and now check again
    strat.checkList(tokens);
  }

  function test_deployment_checklist() public {
    deployStratTest();
  }

  function test_fill_order() public {
    deployStrat();

    execStratWithFillSuccess();
  }

  function test_must_not_fill_order() public {
    deployStrat();

    execStratWithFillFail();
  }

  function test_fill_order_with_slippage_upper() public {
    deployStrat();

    execStratWithFillSuccessAndSlippageUpper();
  }

  function getPrice(AggregatorV3Interface i) internal view returns (uint) {
    (, int price, , ,) = i.latestRoundData();
    return uint(price);
  }

  function getAssetEquivalent(IERC20 asset, uint amount, IERC20 to, AggregatorV3Interface fromOracle, AggregatorV3Interface toOracle) internal view returns (uint price) {
    (, int _fromPrice, , ,) = fromOracle.latestRoundData();
    (, int _toPrice, , ,) = toOracle.latestRoundData();
    uint fromPrice = uint(_fromPrice);
    uint toPrice = uint(_toPrice);

    uint fromPriceDecimals = fromOracle.decimals();
    uint toPriceDecimals = toOracle.decimals();

    if (fromPriceDecimals > toPriceDecimals) {
      price = fromPrice * PRICE_PRECISION / (toPrice * 10 ** (fromPriceDecimals - toPriceDecimals));
    } else {
      price = fromPrice * 10 ** (toPriceDecimals - fromPriceDecimals) * PRICE_PRECISION / toPrice;
    }

    uint fromDecimals = asset.decimals();
    uint toDecimals = to.decimals();

    price = amount * price;

    if (fromDecimals > toDecimals) {
      price = price / (PRICE_PRECISION * 10 ** (fromDecimals - toDecimals));
    } else {
      return amount * price * (10 ** (toDecimals - fromDecimals)) / PRICE_PRECISION;
    }
  }

  function postAndFundOffer(IERC20 outbound, IERC20 inbound, uint gives, uint wants, DirectOracle.Slippage memory slippage) internal returns (uint offerId)
  {
    offerId = strat.newOffer{value: 2 ether}({
      outbound_tkn: outbound,
      inbound_tkn: inbound,
      wants: wants,
      gives: gives,
      pivotId: 0,
      slippage: slippage
    });
  }

  function takeOffer(IERC20 outbound, IERC20 inbound, uint gives, uint wants, uint offerId)
    public
    returns (uint takerGot, uint takerGave, uint bounty)
  {
    // try to snipe one of the offers (using the separate taker account)
    vm.prank(taker);
    (, takerGot, takerGave, bounty,) = mgv.snipes({
      outbound_tkn: $(outbound),
      inbound_tkn: $(inbound),
      targets: wrap_dynamic([offerId, gives, wants, type(uint).max]),
      fillWants: true
    });
  }

  function execStratWithFillSuccess() public {

    // create an offer eth for usdc
    uint makerGivesAmount = 1 ether;
    uint makerWantsAmountUSDC = getAssetEquivalent(weth, makerGivesAmount, usdc, eth_usd, usdc_usd);

    console.log("makerGivesAmount", makerGivesAmount);
    console.log("makerWantsAmountUSDC", makerWantsAmountUSDC);


    uint price = getPrice(eth_usd);

    console.log("Price of ETH in USD", price);

    deal($(weth), $(this), cash(weth, 1));
    weth.transfer($(strat), cash(weth, 1));

    uint offerId = postAndFundOffer(weth, usdc, makerGivesAmount, makerWantsAmountUSDC, DirectOracle.Slippage({
      maxSlippage: 1e5, // 10%
      strict: true
    }));

    deal($(usdc), taker, makerWantsAmountUSDC);

    vm.prank(taker);
    usdc.approve($(strat), type(uint).max);

    (uint takerGot, uint takerGave,) = takeOffer(weth, usdc, makerGivesAmount, makerWantsAmountUSDC, offerId);

    assertEq(takerGot, reader.minusFee($(usdc), $(weth), makerGivesAmount), "taker got wrong amount");
    assertEq(takerGave, makerWantsAmountUSDC, "taker gave wrong amount");

    // assert that neither offer posted by Offer maker are live (= have been retracted)
    MgvStructs.OfferPacked offer_on_usdc = mgv.offers($(weth), $(usdc), offerId);
    assertTrue(!mgv.isLive(offer_on_usdc), "weth->usdc offer should have been retracted");
  }

  function execStratWithFillFail() public {
    // create an offer eth for usdc
    uint makerGivesAmount = 1 ether;
    uint makerWantsAmountUSDC = getAssetEquivalent(weth, makerGivesAmount, usdc, eth_usd, usdc_usd) * 120000 / 100000; // add 10% slippage

    console.log("makerGivesAmount", makerGivesAmount);
    console.log("makerWantsAmountUSDC", makerWantsAmountUSDC);


    uint price = getPrice(eth_usd);

    console.log("Price of ETH in USD", price);

    deal($(weth), $(this), cash(weth, 1));
    weth.transfer($(strat), cash(weth, 1));

    uint offerId = postAndFundOffer(weth, usdc, makerGivesAmount, makerWantsAmountUSDC, DirectOracle.Slippage({
      maxSlippage: 1e5, // 10%
      strict: true
    }));

    deal($(usdc), taker, makerWantsAmountUSDC);

    vm.prank(taker);
    usdc.approve($(strat), type(uint).max);

    (uint takerGot, uint takerGave,) = takeOffer(weth, usdc, makerGivesAmount, makerWantsAmountUSDC, offerId);

    assertEq(takerGot, 0, "taker got wrong amount");
    assertEq(takerGave, 0, "taker gave wrong amount");

    // assert that neither offer posted by Offer maker are live (= have been retracted)
    MgvStructs.OfferPacked offer_on_usdc = mgv.offers($(weth), $(usdc), offerId);
    assertTrue(!mgv.isLive(offer_on_usdc), "weth->usdc offer should have been retracted");
  }

  function execStratWithFillSuccessAndSlippageUpper() public {
     // create an offer eth for usdc
    uint makerGivesAmount = 1 ether;
    uint makerWantsAmountUSDC = getAssetEquivalent(weth, makerGivesAmount, usdc, eth_usd, usdc_usd) * 120000 / 100000; // add 10% slippage

    deal($(weth), $(this), cash(weth, 1));
    weth.transfer($(strat), cash(weth, 1));

    uint offerId = postAndFundOffer(weth, usdc, makerGivesAmount, makerWantsAmountUSDC, DirectOracle.Slippage({
      maxSlippage: 1e5, // 10%
      strict: false
    }));

    deal($(usdc), taker, makerWantsAmountUSDC);

    vm.prank(taker);
    usdc.approve($(strat), type(uint).max);

    (uint takerGot, uint takerGave,) = takeOffer(weth, usdc, makerGivesAmount, makerWantsAmountUSDC, offerId);

    assertEq(takerGot, reader.minusFee($(usdc), $(weth), makerGivesAmount), "taker got wrong amount");
    assertEq(takerGave, makerWantsAmountUSDC, "taker gave wrong amount");

    // assert that neither offer posted by Offer maker are live (= have been retracted)
    MgvStructs.OfferPacked offer_on_usdc = mgv.offers($(weth), $(usdc), offerId);
    assertTrue(!mgv.isLive(offer_on_usdc), "weth->usdc offer should have been retracted");
  }

}