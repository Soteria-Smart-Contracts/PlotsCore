pragma solidity ^0.8.4;

contract Plots_MultiToken_Presale{
    //Token Addresses
    address public VLND = address(0);
    address public USDT = 0xdac17f958d2ee523a2206206994597c13d831ec7;
    address public USDC = 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48;
    
    //Chainlink Price Feeds
    address public USDTPriceFeed = 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46;
    address public USDCPriceFeed = 0x51597f405303C4377E36123cBc172b13269EA163;

    //Admin Address
    address public Admin;

    //Params
    uint256 public SaleStart;
    uint256 public SaleEnd;
    uint256 public PhaseOnePrice;
    uint256 public PhaseTwoPrice;

    uint256 public TotalRaised;
    uint256 public PhaseOneCap;

    enum SalePhase {AwaitingStart, PhaseOne, PhaseTwo, Over};

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