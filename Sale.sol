pragma solidity ^0.8.4;



contract CLS_Crowdsale {
    address payable CLS;
    address payable wETC;
    uint256 public CLS_Sale_Allocation;
    uint256 public Total_wETC_Deposited; 
    uint256 public Allocation_Exchange_Rate = 0;
    uint256 public Total_CLS_Distributed;
    address public CrowdSale_Operator;
    uint256 public Crowdsale_End_Unix;
    
    //DEV WALLETS
    
    address LiquidityAddress = 0xC61A70Fb5F8A967C71c1E9A42374FbE460D0a341; //This address will be used to add the 80% of crowdsale funds as liquidity for wETC-CLS
    
    address Dev_1 = 0x19b2a627Dd49587E021290b3eEF38ea8DE541eE5; //Personal Wallet of one of the developers () 62%
    address Dev_2 = 0xb24f9473Fee391c8FE0ED3fF423E135AaEC8023E; //Personal Wallet of one of the developers () 4.5%
    address Dev_3 = 0xF24f578ea9dFed642Cd41016F863a8cc839e4766; //Personal Wallet of one of the developers () 3%
    address Dev_4 = 0x0000000000000000000000000000000000000000; //Personal Wallet of one of the developers () 6.5%
    address Dev_5 = 0xCe02AC65DFAFAe00b7dB3a1410848aD6e621d3fB; //Personal Wallet of one of the developers () 15%
    address Dev_6 = 0xD73F080b9D12A51292fc22aBb27FE78A502de494; //Personal Wallet of one of the developers () 4.5%
    address Dev_7 = 0x258206BFa2FeD7D8786cE182B7fBe3c3c4976c7B; //Personal Wallet of one of the developers () 4.5%
    
    //Crowdsale Mode struct 
    struct Mode {
        string Sale_Mode_Text;
        uint8 Sale_Mode;
    }
    
    Mode Crowdsale_Mode;
    //Crowdsale Modes
    //1: Before sale preperation Mode
    //2: Sale is Open to buy CLS
    //3: Sale is over, CLS buyer withdrawal period
    //99 Emergency Shutdown mode, in case any issues or bugs need to be dealt with, Safe for buyers, and ETC withdrawls will be available
    
    
    //Crowdsale Contract constructor
    constructor(uint256 Sale_Allocation, address payable _CLS, address payable _wETC){
        CLS_Sale_Allocation = Sale_Allocation;
        CLS = _CLS;
        wETC = _wETC;
        Crowdsale_Mode = Mode("Before sale preperation", 1);
        CrowdSale_Operator = msg.sender;
    }
    
    //Event Declarations
    event CrowdsaleStarted(address Operator, uint256 Crowdsale_Allocation, uint256 Unix_End);
    event CrowdsaleEnded(address Operator, uint256 wETCraised, uint256 BlockTimestamp);
    event wETCdeposited(address Depositor, uint256 Amount);
    event wETCwithdrawn(address Withdrawee, uint256 Amount);
    event CLSwithdrawn(address Withdrawee, uint256 Amount);
    event VariableChange(string Change);
    
    
    
    //Deposit Tracker
    mapping(address => uint256) wETC_Deposited;
    
    
    //Buyer Functions
    
    function DepositETC(uint256 amount) public returns(bool success){
        require(Crowdsale_Mode.Sale_Mode == 2);
        require(block.timestamp < Crowdsale_End_Unix);
        require(amount >= 1000000000000000);
        
        ERC20(wETC).transferFrom(msg.sender, address(this), amount);
        
        wETC_Deposited[msg.sender] = (wETC_Deposited[msg.sender] + amount);
        
        Total_wETC_Deposited = (Total_wETC_Deposited + amount);
        emit wETCdeposited(msg.sender, amount);
        return(success);
    }
    
    //There is a 5% fee for withdrawing deposited wETC
    function WithdrawETC(uint256 amount) public returns(bool success){
        require(amount <= wETC_Deposited[msg.sender]);
        require(Crowdsale_Mode.Sale_Mode != 3 && Crowdsale_Mode.Sale_Mode != 1);
        require(amount >= 1000000000000000);
        uint256 amount_wFee;
        amount_wFee = (amount * 95 / 100);
        
        wETC_Deposited[msg.sender] = (wETC_Deposited[msg.sender] - amount);
        
        ERC20(wETC).transfer(msg.sender, amount_wFee);
        
        Total_wETC_Deposited = (Total_wETC_Deposited - amount_wFee);
        emit wETCwithdrawn(msg.sender, amount);
        return(success);
    }
    
    function WithdrawCLS() public returns(uint256 _CLSwithdrawn){
        require(Crowdsale_Mode.Sale_Mode == 3);
        require(block.timestamp > Crowdsale_End_Unix);
        require(wETC_Deposited[msg.sender] >= 1000000000000000);
        
        
        uint256 CLStoMintandSend;
        CLStoMintandSend = (((wETC_Deposited[msg.sender] / 100000000) * Allocation_Exchange_Rate) / 100000000);
        require((Total_CLS_Distributed + CLStoMintandSend) <= CLS_Sale_Allocation);
        
        wETC_Deposited[msg.sender] = 0;
        
        ERC20(CLS).Mint(msg.sender, CLStoMintandSend);
        
        Total_CLS_Distributed = (Total_CLS_Distributed + CLStoMintandSend);
        emit CLSwithdrawn(msg.sender, CLStoMintandSend);
        return(CLStoMintandSend);
    }
    
    
    
    //Operator Functions
    function StartCrowdsale() public returns(bool success){
        require(msg.sender == CrowdSale_Operator);
        require(ERC20(CLS).CheckMinter(address(this)) == 1);
        require(Crowdsale_Mode.Sale_Mode == 1);
        require(Setup == 1);
        
        Crowdsale_End_Unix = (block.timestamp + 86400);
        Crowdsale_Mode.Sale_Mode_Text = ("Sale is Open to buy CLS");
        Crowdsale_Mode.Sale_Mode = 2;
        
        emit CrowdsaleStarted(msg.sender, CLS_Sale_Allocation, Crowdsale_End_Unix);
        return success;
        
    }
    
    function EndCrowdsale() public returns(bool success){
        require(msg.sender == CrowdSale_Operator);
        require(ERC20(CLS).CheckMinter(address(this)) == 1);
        require(Crowdsale_Mode.Sale_Mode == 2);
        require(block.timestamp > Crowdsale_End_Unix);
        
        Crowdsale_Mode.Sale_Mode_Text = ("Sale is over, Time to withdraw CLS!");
        Crowdsale_Mode.Sale_Mode = 3;
        
        
        Allocation_Exchange_Rate = (((CLS_Sale_Allocation * 100000000) / (Total_wETC_Deposited / 100000000))); 
        
        emit CrowdsaleEnded(msg.sender, Total_wETC_Deposited, block.timestamp);
        return(success);
        
    }
    //This function only works when the crowdsale is in the post-sale mode(3), or in the Emergency mode(99)
    function PullwETC() public returns(bool success){
        require(Crowdsale_Mode.Sale_Mode == 3 || Crowdsale_Mode.Sale_Mode == 99);
        require(block.timestamp > Crowdsale_End_Unix);
        
        bool Multisig;
        Multisig = MultiSignature();
        
        
        uint256 Contract_wETC_Balance;
        Contract_wETC_Balance = ERC20(wETC).balanceOf(address(this));
        
        uint256 LiquidityFunds;
        LiquidityFunds = ((Contract_wETC_Balance * 80) / 100);
        
        uint256 DevFunds;
        DevFunds = ((Contract_wETC_Balance * 20) / 100);
        
        if (Multisig == true){
            ERC20(wETC).transfer(LiquidityAddress, LiquidityFunds);
            ERC20(wETC).transfer(Dev_1, ((DevFunds * 620) / 1000));
            ERC20(wETC).transfer(Dev_2, ((DevFunds * 45) / 1000));
            ERC20(wETC).transfer(Dev_3, ((DevFunds * 30) / 1000));
            ERC20(wETC).transfer(Dev_4, ((DevFunds * 65) / 1000));
            ERC20(wETC).transfer(Dev_5, ((DevFunds * 150) / 1000));
            ERC20(wETC).transfer(Dev_6, ((DevFunds * 45) / 1000));
            ERC20(wETC).transfer(Dev_7, ((DevFunds * 45) / 1000));
        }

        return success;
    }
    
    function Emergency_Mode_Activate() public returns(bool success){
        bool Multisig;
        Multisig = MultiSignature();
        
        if (Multisig == true){
            
        Crowdsale_Mode.Sale_Mode_Text = ("The Developers have multisigned to activate emergencymode on this smart contract");
        Crowdsale_Mode.Sale_Mode = 99;
        
        return(success);
        }
    }

    function Resume_Sale() public returns(bool success){
        bool Multisig;
        Multisig = MultiSignature();
        require(Crowdsale_Mode.Sale_Mode == 99);
        require(block.timestamp < Crowdsale_End_Unix);
        
        if (Multisig == true){
            
        Crowdsale_Mode.Sale_Mode_Text = ("Sale is Open to buy CLS");
        Crowdsale_Mode.Sale_Mode = 2;
        
        return(success);
        }
    }
    
    //Add Resume Crowdsale
    
      //Redundancy
    function ChangeCLSaddy(address payable NewAddy)public returns(bool success, address CLSaddy){
        require(msg.sender == CrowdSale_Operator);
        require(Crowdsale_Mode.Sale_Mode != 3);
        CLS = NewAddy;
        emit VariableChange("Changed CLS Address");
        return(true, CLS);
    }
      //Redundancy
    function ChangeWETCaddy(address payable NewAddy)public returns(bool success, address wETCaddy){
        require(msg.sender == CrowdSale_Operator);
        require(Crowdsale_Mode.Sale_Mode == 1);
        wETC = NewAddy;
        emit VariableChange("Changed wETC Address");
        return(true, CLS);
    }
    
    //Call Functions
    function GetContractMode() public view returns(uint256, string memory){
        return (Crowdsale_Mode.Sale_Mode, Crowdsale_Mode.Sale_Mode_Text);
        
    }
    
    function GetwETCdeposited(address _address) public view returns(uint256){
        return (wETC_Deposited[_address]);
    }
    //_______________________________________________________________________________________________________________________________________________________________            
    //_______________________________________________________________________________________________________________________________________________________________
    
    
    //Multi-Sig Requirement for Fund Extraction post crowsale by Dev Team to reduce attack likelyness aswell as remove central point of authority
    uint8 public Signatures;
    address public SigAddress1;
    address public SigAddress2;
    address public SigAddress3;
    uint8 public Setup;
    bool public Verified;
    
    mapping(address => uint8) Signed;
    
    event MultiSigSet(bool Success);
    event MultiSigVerified(bool Success);
    

    
    function MultiSigSetup(address _1, address _2, address _3) public returns(bool success){
        require(Setup == 0);
        require(msg.sender == CrowdSale_Operator);
        require(Crowdsale_Mode.Sale_Mode == 1);
        
        SigAddress1 = _1;
        SigAddress2 = _2;
        SigAddress3 = _3;
        
        Setup = 1;
        
        emit MultiSigSet(true);
        return(success);
    }
    
    function MultiSignature() internal returns(bool AllowTransaction){
        require(msg.sender == SigAddress1 || msg.sender == SigAddress2 || msg.sender == SigAddress3);
        require(Signed[msg.sender] == 0);
        require(Setup == 1);
        Signed[msg.sender] = 1;
        
        if (Signatures == 1){
            Signatures = 0;
            Signed[SigAddress1] = 0;
            Signed[SigAddress2] = 0;
            Signed[SigAddress3] = 0;
            return(true);
        }
        
        if (Signatures == 0){
            Signatures = (Signatures + 1);
            return(false);
        }

    }
    
    function SweepSignatures() public returns(bool success){
        require(msg.sender == CrowdSale_Operator);
        require(Setup == 1);
        
        Signed[SigAddress1] = 0;
        Signed[SigAddress2] = 0;
        Signed[SigAddress3] = 0;
        
        Signatures = 0;
        
        return(success);
        
    }
    
    
    function MultiSigVerification() public returns(bool success){
        require(Verified == false);
        bool Verify;
        Verify = MultiSignature();
        
        if (Verify == true){
            Verified = true;
            emit MultiSigVerified(true);
        }
        
        return(Verify);
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