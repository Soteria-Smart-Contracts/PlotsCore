pragma solidity ^0.8.4;

contract Plots_MultiToken_Presale{
    //Token Addresses
    address public VLND;
    address public USDT;
    address public USDC;

    //Admin Address
    address public Admin;

    //Params
    uint256 public SaleStart;
    uint256 public PhaseOnePrice;
    uint256 public PhaseTwoPrice;

    uint256 public PhaseOneCap;

    enum SalePhase {AwaitingStart, PhaseOne, PhaseTwo, Over}

    function GetSaleStatus() public view returns(SalePhase){
        if(block.timestamp < SaleStart){
            return SalePhase.AwaitingStart;
        }
        if(block.timestamp < PhaseOneEnd){
            return SalePhase.PhaseOne;
        }
        if(block.timestamp < PhaseTwoEnd){
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