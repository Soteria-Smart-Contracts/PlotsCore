pragma solidity ^0.8.4;

contract Plots_MultiToken_Presale{
    //Token Addresses
    address public VLND = address(0);
    address public USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    //Chainlink Price Feeds
    address public USDTPriceFeed = 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46;

    //Admin Address
    address public Admin;

    //Params
    uint256 public SaleStart;
    uint256 public SaleEnd;
    uint256 public PhaseOnePrice;
    uint256 public PhaseTwoPrice;

    uint256 public TotalRaised;
    uint256 public PhaseOneCap;

    enum SalePhase {AwaitingStart, PhaseOne, PhaseTwo, Over}
    
    //Getter Functions

    function GetSaleStatus() public view returns(SalePhase){
        if(block.timestamp < SaleStart){
            return SalePhase.AwaitingStart;
        }
        else if(block.timestamp > SaleEnd){
            return SalePhase.Over;
        }
        else if(TotalRaised < PhaseOneCap){
            return SalePhase.PhaseOne;
        }
        else if(TotalRaised >= PhaseOneCap){
            return SalePhase.PhaseTwo;
        }
        return SalePhase.Over;
    }

    function GetVLNDPrice() public view returns(uint256){
        if(GetSaleStatus() == SalePhase.PhaseOne){
            return PhaseOnePrice;
        }
        else if(GetSaleStatus() == SalePhase.PhaseTwo){
            return PhaseTwoPrice;
        }
        return 0;
    }

    function GetUSDTExchangeRate() public view returns(uint256 USDT){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(USDTPriceFeed);
        (,int priceusdt,,,) = priceFeed.latestRoundData();
        USDT = uint256(priceusdt);
        return (USDT, USDC);
    }

}


interface ERC20 {
  function balanceOf(address owner) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint value) external returns (bool);
  function Mint(address _MintTo, uint256 _MintAmount) external;
  function transfer(address to, uint value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool); 
  function totalSupply() external view returns (uint);
  function CheckMinter(address AddytoCheck) external view returns(uint);
}

interface AggregatorV3Interface {
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}