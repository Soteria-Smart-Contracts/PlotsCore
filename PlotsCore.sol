// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

contract PlotsCoreV1 {
    //Variable and pointer Declarations
    address payable public Treasury;
    address payable public FeeReceiver;
    uint256 public CurrentRewardFee;
    address public LendContract;
    address[] public ListedCollections;
    mapping(address => uint256) public ListedCollectionsIndex;
    mapping(OwnershipPercent => uint8) public OwnershipPercentages;
    address[] public AvailableLoanContracts;
    mapping(address => uint256) public AvailableLoanContractsIndex;


    enum ListingType{
        Ownership,
        Usage
    }

    enum LengthOption{ 
        ThreeMonths,
        SixMonths
    }

    enum OwnershipPercent{
        Zero,
        Ten,
        TwentyFive
    }
    
    struct Listing{
        address Lister;
        address Collection;
        uint256 TokenId;
        ListingType OwnershipOption;
    }

    mapping(address => bool) public Admins;
    modifier OnlyAdmin(){
        require(Admins[msg.sender], "Only Admin");
        _;
    }

    mapping(address => mapping(address => uint256)) public OwnershipByPurchase;

    //Listings for assets available for borrowing
    mapping(address => Listing[]) public ListingsByCollection;
    //create a mapping that maps a token id to a listing index
    mapping(address => mapping(uint256 => uint256)) public ListingsByCollectionIndex;

    mapping(address => address[]) public AllUserLoans; //Outgoing loans
    mapping(address => mapping(address => uint256)) public AllUserLoansIndex;

    mapping(address => address[]) public AllUserBorrows; //Incoming loans
    mapping(address => mapping(address => uint256)) public AllUserBorrowsIndex;


    constructor(address [] memory _admins, address payable _feeReceiver){
        Treasury =  payable(new PlotsTreasury(address(this)));
        FeeReceiver = _feeReceiver;

        for(uint256 i = 0; i < _admins.length; i++){
            Admins[_admins[i]] = true;
        }
        Admins[msg.sender] = true;
        Admins[Treasury] = true;

        OwnershipPercentages[OwnershipPercent.Zero] = 0;
        OwnershipPercentages[OwnershipPercent.Ten] = 10;
        OwnershipPercentages[OwnershipPercent.TwentyFive] = 25;
    }

    //Loan Functions

    function BorrowToken(address Collection, uint256 TokenId, LengthOption Duration, OwnershipPercent Ownership) public payable {
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(ListingsByCollectionIndex[Collection][TokenId] != 0, "Token not listed");

        address LoanContract;
        if(AvailableLoanContracts.length > 0){
            LoanContract = AvailableLoanContracts[AvailableLoanContracts.length - 1];
            AvailableLoanContractsIndex[LoanContract] = 0;
            AvailableLoanContracts.pop();
        }
        

        uint256 TokenValue = PlotsTreasury(Treasury).GetTokenValueFloorAdjusted(Collection, TokenId);
        uint256 DurationUnix = (uint8(Duration) + 1) * 90 days;
        
        if(ListingsByCollection[Collection][TokenId].OwnershipOption == ListingType.Ownership){
            uint256 Fee = (TokenValue * 25) / 1000;
            uint256 BorrowCost = Fee;
            if(Ownership == OwnershipPercent.Ten){
                BorrowCost += (TokenValue * 10) / 100;
            }
            else if(Ownership == OwnershipPercent.TwentyFive){
                BorrowCost += (TokenValue * 25) / 100;
            }
            require(msg.value >= BorrowCost, "Not enough ether sent");
            PlotsTreasury(Treasury).SendToLoan(NewLoanContract, Collection, TokenId);
        }
        else{
            require(Ownership == OwnershipPercent.Zero, "Ownership must be zero");
            require(PlotsLend(LendContract).GetTokenLocation(Collection, TokenId) == address(this), "Token not in lending contract");
            PlotsLend(LendContract).SendToLoan(NewLoanContract, Collection, TokenId);
        }

        //send the 2.5% fee to the fee receiver
        PlotsTreasury(Treasury).SendEther(FeeReceiver, (TokenValue * 25) / 1000);
        PlotsTreasury(Treasury).SendEther(payable(Treasury), address(this).balance);

        RemoveListingFromCollection(Collection, TokenId);
        AddLoanToBorrowerAndLender(msg.sender, ListingsByCollection[Collection][TokenId].Lister, NewLoanContract);
        NFTLoan(NewLoanContract).BeginLoan(Ownership, ListingsByCollection[Collection][TokenId].Lister , msg.sender, Collection, TokenId, DurationUnix, TokenValue);
        OwnershipByPurchase[Collection][msg.sender] = TokenId;
    }

    function CloseLoan(address LoanContract) public{
        require(NFTLoan(LoanContract).Borrower() == msg.sender || NFTLoan(LoanContract).Owner() == msg.sender, "Not owner of loan");
        require(NFTLoan(LoanContract).LoanEndTime() <= block.timestamp, "Loan not ended yet");
        require(NFTLoan(LoanContract).Active(), "Loan not active");

        address Collection = NFTLoan(LoanContract).TokenCollection();
        uint256 TokenId = NFTLoan(LoanContract).TokenID();
        address Borrower = NFTLoan(LoanContract).Borrower();
        uint256 OwnershipPercentage;
        address ReturnContract;
        uint256 CollateralValue;

        if(NFTLoan(LoanContract).OwnershipType() == OwnershipPercent.Zero){
            OwnershipPercentage = 0;
            ReturnContract = LendContract;
            CollateralValue = 0;
            NFTLoan(LoanContract).EndLoan(LendContract);
            PlotsLend(LendContract).ReturnedFromLoan(Collection, TokenId);
        }
        else if(NFTLoan(LoanContract).OwnershipType() == OwnershipPercent.Ten){
            OwnershipPercentage = 10;
            ReturnContract = Treasury;
            CollateralValue = (PlotsTreasury(Treasury).GetTokenValueFloorAdjusted(Collection, TokenId) * OwnershipPercentage) / 100;
            NFTLoan(LoanContract).EndLoan(Treasury);
            PlotsTreasury(Treasury).ReturnedFromLoan(Collection, TokenId);
            PlotsTreasury(Treasury).SendEther(payable(Borrower), CollateralValue);

        }
        else if(NFTLoan(LoanContract).OwnershipType() == OwnershipPercent.TwentyFive){
            OwnershipPercentage = 25;
            ReturnContract = Treasury;
            CollateralValue = (PlotsTreasury(Treasury).GetTokenValueFloorAdjusted(Collection, TokenId) * OwnershipPercentage) / 100;
            NFTLoan(LoanContract).EndLoan(Treasury);
            PlotsTreasury(Treasury).ReturnedFromLoan(Collection, TokenId);
            PlotsTreasury(Treasury).SendEther(payable(Borrower), CollateralValue);
        }        
    }

    // Listings ---------------------------------------------------------------------------------

    function ListToken(address Collection, uint256 TokenId) public{
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(ListingsByCollectionIndex[Collection][TokenId] == 0, "Token already listed");

        if(Admins[msg.sender]){
            require(ERC721(Collection).ownerOf(TokenId) == Treasury, "Token not owned by treasury");
            require(ListingsByCollectionIndex[Collection][TokenId] == 0 && ListingsByCollection[Collection][0].TokenId != TokenId, "Token already listed");
            ListingsByCollection[Collection].push(Listing(Treasury, Collection, TokenId, ListingType.Ownership));
        }
        else{
            //require that the loan contract is the owner of the token and that the token depositors address is the msg.sender and that the token is not already listed
            require(ERC721(Collection).ownerOf(TokenId) == address(LendContract), "Token not owned by lending contract");
            require(PlotsLend(LendContract).GetTokenDepositor(Collection, TokenId) == msg.sender, "Not owner of token");
            require(ListingsByCollectionIndex[Collection][TokenId] == 0 && ListingsByCollection[Collection][0].TokenId != TokenId, "Token already listed");
            ListingsByCollection[Collection].push(Listing(msg.sender, Collection, TokenId, ListingType.Usage));
        }

        ListingsByCollectionIndex[Collection][TokenId] = ListingsByCollection[Collection].length - 1;
    }

    //function DelistToken
    function DelistToken(address Collection, uint256 TokenId) public{
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(ListingsByCollectionIndex[Collection][TokenId] != 0, "Token not listed");
        if(ListingsByCollection[Collection][ListingsByCollectionIndex[Collection][TokenId]].Lister == Treasury){
            require(Admins[msg.sender], "Only Admin");
        }
        else{
            require(ListingsByCollection[Collection][ListingsByCollectionIndex[Collection][TokenId]].Lister == msg.sender, "Not owner of listing");
        }

        RemoveListingFromCollection(Collection, TokenId);
    }


    //function ChangeOwnershipPercentage on a loan

    function ChangeOwnershipPercentage(address LoanContract, OwnershipPercent Ownership) public payable {
        require(NFTLoan(LoanContract).Borrower() == msg.sender, "Not borrower of loan");
        require(NFTLoan(LoanContract).Active(), "Loan not active");
        OwnershipPercent CurrentOwnership = NFTLoan(LoanContract).OwnershipType();
        require(CurrentOwnership != Ownership, "Ownership already set to this");

        uint256 CurrentValue = PlotsTreasury(Treasury).GetTokenValueFloorAdjusted(NFTLoan(LoanContract).TokenCollection(), NFTLoan(LoanContract).TokenID());
        uint256 CollateralValueChange;

        if(CurrentOwnership == OwnershipPercent.Ten){
            //15% Inclusive of a 1% fee
            CollateralValueChange = (CurrentValue * 16) / 100;
            require(msg.value >= CollateralValueChange, "Not enough ether sent");
        }
        else if(Ownership == OwnershipPercent.TwentyFive){
            //15% Inclusive of a 1% fee
            CollateralValueChange = (CurrentValue * 14) / 100;
            PlotsTreasury(Treasury).SendEther(payable(NFTLoan(LoanContract).Borrower()), CollateralValueChange);
        }

        NFTLoan(LoanContract).UpdateBorrowerRewardShare(Ownership);
    }

    //



    //Public View Functions

    function GetCollectionListings(address _collection) public view returns(Listing[] memory){
        return ListingsByCollection[_collection];
    }

    function GetSingularListing(address _collection, uint256 _tokenId) public view returns(Listing memory){
        return ListingsByCollection[_collection][_tokenId];
    }

    function GetListedCollections() public view returns(address[] memory){
        return ListedCollections;
    }
    
    //Function to allow frontend see all user loaned tokens (that they put up collateral to borrow)
    function GetUserLoans(address _user) public view returns(address[] memory){
        return AllUserLoans[_user];
    }

    //Listings by user
    function GetUserListings(address _collection) public view returns(Listing[] memory){
        Listing[] memory _listings = new Listing[](ListingsByCollection[_collection].length);
        for(uint256 i = 0; i < ListingsByCollection[_collection].length; i++){
            _listings[i] = ListingsByCollection[_collection][i];
        }
        return _listings;
        //unfortunately we cannot push to a memory array so the returned aarray will have empty values
    }


    function GetListedCollectionWithPrices(address _collection) public view returns(Listing[] memory, uint256[] memory Prices){
        uint256[] memory _prices = new uint256[](ListingsByCollection[_collection].length);
        for(uint256 i = 0; i < ListingsByCollection[_collection].length; i++){
            if(ListingsByCollection[_collection][i].OwnershipOption == ListingType.Ownership){
                _prices[i] = PlotsTreasury(Treasury).GetTokenValueFloorAdjusted(_collection, ListingsByCollection[_collection][i].TokenId);
            }
            else{
                _prices[i] = 0;
            }
        }
        return (GetCollectionListings(_collection), _prices);
    }

    //Internal Functions

    function AddListingToCollection(address _collection, uint256 _tokenId, Listing memory _listing) internal{
        ListingsByCollection[_collection].push(_listing);
        ListingsByCollectionIndex[_collection][_tokenId] = ListingsByCollection[_collection].length - 1;
    }

    function RemoveListingFromCollection(address _collection, uint256 _tokenId) internal{
        ListingsByCollection[_collection][ListingsByCollectionIndex[_collection][_tokenId]] = ListingsByCollection[_collection][ListingsByCollection[_collection].length - 1];
        ListingsByCollectionIndex[_collection][ListingsByCollection[_collection][ListingsByCollectionIndex[_collection][_tokenId]].TokenId] = ListingsByCollectionIndex[_collection][_tokenId];
        ListingsByCollection[_collection].pop();
    }

    //add loan to a borrower and a lender with just the loan address IN ONE function
    function AddLoanToBorrowerAndLender(address Borrower, address Lender, address _loan) internal{
        AllUserLoans[Borrower].push(_loan);
        AllUserLoansIndex[Borrower][_loan] = AllUserLoans[Borrower].length - 1;

        AllUserBorrows[Lender].push(_loan);
        AllUserBorrowsIndex[Lender][_loan] = AllUserBorrows[Lender].length - 1;
    }

    //remove loan from a borrower and a lender with just the loan address IN ONE function
    function RemoveLoanFromBorrowerAndLender(address Borrower, address Lender, address _loan) internal{
        AllUserLoans[Borrower][AllUserLoansIndex[Borrower][_loan]] = AllUserLoans[Borrower][AllUserLoans[Borrower].length - 1];
        AllUserLoansIndex[Borrower][AllUserLoans[Borrower][AllUserLoansIndex[Borrower][_loan]]] = AllUserLoansIndex[Borrower][_loan];
        AllUserLoans[Borrower].pop();

        AllUserBorrows[Lender][AllUserBorrowsIndex[Lender][_loan]] = AllUserBorrows[Lender][AllUserBorrows[Lender].length - 1];
        AllUserBorrowsIndex[Lender][AllUserBorrows[Lender][AllUserBorrowsIndex[Lender][_loan]]] = AllUserBorrowsIndex[Lender][_loan];
        AllUserBorrows[Lender].pop();
    }


    //Only Admin Functions

    function ListTokenForOwnership(address Collection, uint256 TokenId) public OnlyAdmin{
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(ListingsByCollectionIndex[Collection][TokenId] == 0, "Token already listed");
        require(ERC721(Collection).ownerOf(TokenId) == Treasury, "Token not owned by treasury");


        ListingsByCollection[Collection].push(Listing(Treasury, Collection, TokenId, ListingType.Ownership));
        ListingsByCollectionIndex[Collection][TokenId] = ListingsByCollection[Collection].length - 1;
    }

    function ChangeFeeReceiver(address payable NewReceiver) public OnlyAdmin{
        FeeReceiver = NewReceiver;
    }

    function ChangeRewardFee(uint256 NewFee) public OnlyAdmin{
        require(NewFee <= 1500, "Fee must be less than 15%");
        CurrentRewardFee = NewFee;
    }

    function AddCollection(address _collection) public OnlyAdmin{
        ListedCollections.push(_collection);
        ListedCollectionsIndex[_collection] = ListedCollections.length - 1;
    }

    function RemoveCollection(address _collection) public OnlyAdmin{
        uint256 index = ListedCollectionsIndex[_collection];
        ListedCollections[index] = ListedCollections[ListedCollections.length - 1];
        ListedCollectionsIndex[ListedCollections[index]] = index;
        ListedCollections.pop();
    }
}

contract PlotsTreasury{
    //Variable and pointer Declarations
    address public PlotsCoreContract;

    //mapping of all collections to a floor price
    mapping(address => uint256) public CollectionFloorPrice;
    mapping(address => mapping(uint256 => uint256)) public TokenFloorFactor;
    mapping(address => mapping(uint256 => address)) public TokenLocation;


    modifier OnlyCore(){
        require(msg.sender == address(PlotsCoreContract), "Only Core");
        _;
    }

    //only admin modifier using the core contract
    modifier OnlyAdmin(){
        require(PlotsCoreV1(PlotsCoreContract).Admins(msg.sender) == true || msg.sender == PlotsCoreContract, "Only Admin");
        _;
    }

    constructor(address Core){
        PlotsCoreContract = Core;
    }

    //allow admin to deposit nft into treasury
    function DepositNFT(address Collection, uint256 TokenId, uint256 EtherCost) public OnlyAdmin {
        require(ERC721(Collection).ownerOf(TokenId) == msg.sender, "Not owner of token");
        ERC721(Collection).transferFrom(msg.sender, address(PlotsCoreContract), TokenId);

        //calculate floor factor
        TokenFloorFactor[Collection][TokenId] = (EtherCost / CollectionFloorPrice[Collection]);
    }

    //allow admin to withdraw nft from treasury

    function WithdrawNFT(address Collection, uint256 TokenId) public OnlyAdmin {
        require(ERC721(Collection).ownerOf(TokenId) == address(PlotsCoreContract), "Not owner of token");
        ERC721(Collection).transferFrom(address(PlotsCoreContract), msg.sender, TokenId);

        //check if listed, if so remove listing
        if(PlotsCoreV1(PlotsCoreContract).ListingsByCollectionIndex(Collection, TokenId) != 0){
            PlotsCoreV1(PlotsCoreContract).DelistToken(Collection, TokenId);
        }

        TokenFloorFactor[Collection][TokenId] = 0;
    }

    function SendEther(address payable Recipient, uint256 Amount) public OnlyAdmin {
        require(address(this).balance >= Amount, "Not enough ether in treasury");
        Recipient.transfer(Amount);
    }

    function SendERC20(address Token, address Recipient, uint256 Amount) public OnlyAdmin {
        ERC20(Token).transfer(Recipient, Amount);
    }

    //allow admin to set floor price for multiple collections at once, with an array with the collections and an array with the floor prices
    function SetFloorPrice(address[] memory Collections, uint256[] memory FloorPrices) public OnlyAdmin{
        require(Collections.length == FloorPrices.length, "Arrays not same length");
        for(uint256 i = 0; i < Collections.length; i++){
            CollectionFloorPrice[Collections[i]] = FloorPrices[i];
        }
    }

    //OnlyCore Functions

    function SendToLoan(address LoanContract, address Collection, uint256 TokenID) external OnlyCore{
        ERC721(Collection).transferFrom(address(this), LoanContract, TokenID);

        TokenLocation[Collection][TokenID] = LoanContract;
    }

    //return from loan (transferfrom the token location back to the treeasury, set token location to this)
    function ReturnedFromLoan(address Collection, uint256 TokenID) external OnlyCore(){
        require(ERC721(Collection).ownerOf(TokenID) == address(this), "Token not in treasury");
        
        TokenLocation[Collection][TokenID] = address(this);
    }


    function GetFloorPrice(address Collection) public view returns(uint256){
        return CollectionFloorPrice[Collection];
    }

    function GetFloorFactor(address Collection, uint256 TokenId) public view returns(uint256){
        return TokenFloorFactor[Collection][TokenId];
    }

    function GetTokenValueFloorAdjusted(address Collection, uint256 TokenId) public view returns(uint256){
        return CollectionFloorPrice[Collection] * TokenFloorFactor[Collection][TokenId];
    }

    receive() external payable{}

}

contract PlotsLend{
    //Variable and pointer Declarations
    address public PlotsCoreContract;

    constructor(address Core){
        PlotsCoreContract = Core;
        
    }

    struct Token{
        address Collection;
        uint256 TokenId;
    }

    mapping(address => mapping(uint256 => address)) public TokenDepositor;
    mapping(address => mapping(uint256 => address)) public TokenLocation;

    //all deposited tokens array mapping
    mapping(address => Token[]) public AllUserTokens;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public AllUserTokensIndex;

    //allow a user to deposit a token into the lending contract from any collection that is listed on the core contract
    function DepositToken(address Collection, uint256 TokenId) public{
        require(ERC721(Collection).ownerOf(TokenId) == msg.sender, "Not owner of token");
        ERC721(Collection).transferFrom(msg.sender, address(this), TokenId);

        TokenDepositor[Collection][TokenId] = msg.sender;
        TokenLocation[Collection][TokenId] = address(this);
        AllUserTokens[msg.sender].push(Token(Collection, TokenId));
        AllUserTokensIndex[msg.sender][Collection][TokenId] = AllUserTokens[msg.sender].length - 1;
    }

    function WithdrawToken(address Collection, uint256 TokenId) public{
        require(ERC721(Collection).ownerOf(TokenId) == PlotsCoreContract, "Not owner of token");
        require(TokenLocation[Collection][TokenId] == address(this), "Token not in lending contract");
        ERC721(Collection).transferFrom(address(this), msg.sender, TokenId);

        TokenDepositor[Collection][TokenId] = address(0);
        TokenLocation[Collection][TokenId] = address(0);
        AllUserTokens[msg.sender][AllUserTokensIndex[msg.sender][Collection][TokenId]] = AllUserTokens[msg.sender][AllUserTokens[msg.sender].length - 1];
        AllUserTokens[msg.sender].pop();
        AllUserTokensIndex[msg.sender][Collection][AllUserTokens[msg.sender][AllUserTokensIndex[msg.sender][Collection][TokenId]].TokenId] = AllUserTokensIndex[msg.sender][Collection][TokenId];
        AllUserTokensIndex[msg.sender][Collection][TokenId] = 0;
    }

    //send and return from loan functions

    function SendToLoan(address LoanContract, address Collection, uint256 TokenID) external {
        require(TokenDepositor[Collection][TokenID] == msg.sender, "Not owner of token");
        ERC721(Collection).transferFrom(address(this), LoanContract, TokenID);

        TokenLocation[Collection][TokenID] = LoanContract;
    }

    function ReturnedFromLoan(address Collection, uint256 TokenID) external {
        require(ERC721(Collection).ownerOf(TokenID) == address(this), "Token not in User Portfolio");
        
        TokenLocation[Collection][TokenID] = address(this);
    }

    //View Functions 

    function GetUserTokens(address _user) public view returns(Token[] memory){
        return AllUserTokens[_user];
    }

    function GetTokenDepositor(address Collection, uint256 TokenId) public view returns(address){
        return TokenDepositor[Collection][TokenId];
    }

    function GetTokenLocation(address Collection, uint256 TokenId) public view returns(address){
        return TokenLocation[Collection][TokenId];
    }
}

contract NFTLoan{
    address public Manager;
    address public TokenCollection;
    uint256 public TokenID;

    address public Owner;
    address public Borrower;
    PlotsCoreV1.OwnershipPercent public OwnershipType;
    uint256 public LoanEndTime;
    uint256 public InitialValue;

    uint256 public BorrowerRewardShare; //In Basis Points, zero if no loan exists for this token

    //Use Counter for statistics
    uint256 public UseCounter;
    bool public Active;


    modifier OnlyManager(){
        require(msg.sender == Manager, "Only Manager");
        _;
    }

    constructor(){
        Manager = msg.sender;
    }

    function BeginLoan(PlotsCoreV1.OwnershipPercent Ownership, address TokenOwner, address TokenBorrower, address Collection, uint256 TokenId, uint256 Duration, uint256 InitialVal) public OnlyManager {
        require(msg.sender == Manager, "Only Loans Or Treasury Contract can interact with this contract");
        require(ERC721(Collection).ownerOf(TokenId) == address(this), "Token not in loan");

        TokenCollection = Collection;
        TokenID = TokenId;
        Owner = TokenOwner;
        Borrower = TokenBorrower;
        OwnershipType = Ownership;
        LoanEndTime = block.timestamp + Duration;
        InitialValue = InitialVal;

        if(Ownership == PlotsCoreV1.OwnershipPercent.Zero){
            BorrowerRewardShare = 3000;
        }
        else if(Ownership == PlotsCoreV1.OwnershipPercent.Ten){
            BorrowerRewardShare = 5000;
        }
        else if(Ownership == PlotsCoreV1.OwnershipPercent.TwentyFive){
            BorrowerRewardShare = 6500;
        }

        Active = true;
    }

    function EndLoan(address Origin) public OnlyManager {
        require(msg.sender == Manager, "Only Loans Or Treasury Contract can interact with this contract");
        require(LoanEndTime <= block.timestamp, "Loan not ended yet");
        ERC721(TokenCollection).transferFrom(address(this), Origin, TokenID);
        
        TokenCollection = address(0);
        TokenID = 0;
        Owner = address(0);
        Borrower = address(0);
        BorrowerRewardShare = 0;
        UseCounter++;
        Active = false;
    }

    function DisperseRewards(address RewardToken) public {
        uint256 RewardBalance = ERC20(RewardToken).balanceOf(address(this));
        require(RewardBalance > 0, "No rewards to disperse");
        //check core contract for fee percentage and fee receiver, calculate fee and send to fee receiver
        uint256 Fee = (RewardBalance * PlotsCoreV1(Manager).CurrentRewardFee()) / 10000;
        ERC20(RewardToken).transfer(PlotsCoreV1(Manager).FeeReceiver(), Fee);

        uint256 OwnerReward = (RewardBalance * (10000 - BorrowerRewardShare)) / 10000;
        
        ERC20(RewardToken).transfer(Owner, OwnerReward);
        ERC20(RewardToken).transfer(Borrower, ERC20(RewardToken).balanceOf(address(this)));
    }

    //update borrower reward share (only manager)
    function UpdateBorrowerRewardShare(PlotsCoreV1.OwnershipPercent Ownership) public OnlyManager {
        require(Ownership != OwnershipType, "Ownership already set to this");

        BorrowerRewardShare = 0;

        if(Ownership == PlotsCoreV1.OwnershipPercent.Ten){
            BorrowerRewardShare = 5000;
        }
        else if(Ownership == PlotsCoreV1.OwnershipPercent.TwentyFive){
            BorrowerRewardShare = 6500;
        }
    }

}



interface ERC721 {
    function balanceOf(address _owner) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external payable;
    function transferFrom(address _from, address _to, uint256 _tokenId) external payable;
    function approve(address _approved, uint256 _tokenId) external payable;
    function setApprovalForAll(address _operator, bool _approved) external;
    function getApproved(uint256 _tokenId) external view returns (address);
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}

interface ERC20 {
  function balanceOf(address owner) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 value) external returns (bool);
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool); 
  function totalSupply() external view returns (uint256);
  function Burn(uint256 _BurnAmount) external;
}