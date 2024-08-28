// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract PlotsCore {
    //Variable and pointer Declarations
    address payable public Treasury;
    address public LendContract;
    address payable public FeeReceiver;

    uint256 public RewardFee;
    uint256 public LockedValue;
    address[] public ListedCollections;
    mapping(address => bool) public ListedCollectionsMap;
    mapping(address => uint256) public ListedCollectionsIndex;

    mapping(address => bool) public Blacklisted;

    enum LengthOption{ 
        ThreeMonths,
        SixMonths
    }
    
    struct Listing{
        address Lister;
        address Collection;
        uint256 TokenId;
    }

    struct LoanInfo{
        address Collection;
        uint256 ID; 
        address Lender;
        address Borrower;
    }

    mapping(address => bool) public Admins;
    modifier OnlyAdmin(){
        require(Admins[msg.sender], "Only Admin");
        _;
    }

    modifier NotBlacklisted(){
        require(Blacklisted[msg.sender] == false, "Only Admin");
        _;
    }

    mapping(address => mapping(uint256 => address)) public OwnershipByPurchase;
    mapping(address => mapping(uint256 => uint256)) public UsageExpirationUnix;

    mapping(address => Listing[]) public ListingsByCollection;
    mapping(address => mapping(uint256 => uint256)) public ListingsByCollectionIndex;
    mapping(address => Listing[]) public ListingsByUser;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public ListingsByUserIndex;

    mapping(address => mapping(uint256 => bool)) public ListedBool;
    mapping(address => mapping(uint256 => bool)) public InLoanBool;

    LoanInfo[] public AllLoans;
    mapping(address => mapping(uint256 => uint256)) public AllLoansIndex;

    mapping(address => uint256[]) public AllUserLoans; //Outgoing loans
    mapping(address => mapping(uint256 => uint256)) public AllUserLoansIndex;

    mapping(address => uint256[]) public AllUserBorrows; //Incoming loans
    mapping(address => mapping(uint256 => uint256)) public AllUserBorrowsIndex;

    mapping(address => bool) public ActiveLoan; // Track active loan per user

    constructor(address [] memory _admins, address payable _feeReceiver){
        FeeReceiver = _feeReceiver;

        for(uint256 i = 0; i < _admins.length; i++){
            Admins[_admins[i]] = true;
        }
        Admins[msg.sender] = true;
        Admins[Treasury] = true;
    }

    // Can only be set once
    function SetPeripheryContracts(address payable _treasury, address _lendContract) public OnlyAdmin{
        require(Treasury == address(0) && LendContract == address(0), "Already set");
        require(PlotsTreasury(_treasury).PlotsCoreContract() == address(this), "Invalid treasury contract");
        require(PlotsLend(_lendContract).PlotsCoreContract() == address(this), "Invalid lend contract");
        Treasury = _treasury;
        LendContract = _lendContract;
    }

    //TODO: Fix Duration for only P2p
    function BorrowToken(address Collection, uint256 TokenId, LengthOption Duration) public NotBlacklisted payable {
        require(ListedCollectionsMap[Collection] == true, "Collection N/Listed");
        require(ActiveLoan[msg.sender] == false, "User already has an active loan"); // Check for active loan
        uint256 TokenIndex = ListingsByCollectionIndex[Collection][TokenId];
        require(ListingsByCollection[Collection][TokenIndex].Lister != address(0), "Token N/Listed");

        if(ListingsByCollection[Collection][TokenIndex].Lister != Treasury){
            if(Duration == LengthOption.ThreeMonths){
                UsageExpirationUnix[Collection][TokenId] = block.timestamp + 7776000;
            }
            else{
                UsageExpirationUnix[Collection][TokenId] = block.timestamp + 15552000;
            }
        }

        AddLoanToBorrowerAndLender(msg.sender, ListingsByCollection[Collection][TokenIndex].Lister, Collection, TokenId);
        RemoveListingFromUser(ListingsByCollection[Collection][TokenIndex].Lister, Collection, TokenId);
        RemoveListingFromCollection(Collection, TokenId);

        OwnershipByPurchase[Collection][TokenId] = msg.sender;
        ListedBool[Collection][TokenId] = false;
        InLoanBool[Collection][TokenId] = true;
        
        ActiveLoan[msg.sender] = true; // Track active loan
    }

    function CloseLoan(address Collection, uint256 ID) public{
        require(AllLoans[AllLoansIndex[Collection][ID]].Borrower == msg.sender || Admins[msg.sender] || AllLoans[AllLoansIndex[Collection][ID]].Lender == msg.sender && UsageExpirationUnix[Collection][ID] < block.timestamp,
            "Invalid loan"
        );

        address Borrower = AllLoans[AllLoansIndex[Collection][ID]].Borrower;
        address Lender = AllLoans[AllLoansIndex[Collection][ID]].Lender;

        InLoanBool[Collection][ID] = false;

        AllLoansIndex[Collection][ID] = 0;
        OwnershipByPurchase[Collection][ID] = address(0);
        UsageExpirationUnix[Collection][ID] = 0;
        RemoveLoanFromBorrowerAndLender(Borrower, address(0), Collection, ID);

   
        if(Lender == Treasury){
            AddListingToCollection(Collection, ID, Listing(Treasury, Collection, ID));
            AddListingToUser(Treasury, Collection, ID, Listing(Lender, Collection, ID));
            ListedBool[Collection][ID] = true;
        }
        else{
            PlotsLend(LendContract).Autowithdraw(Collection, ID);
        }

        ActiveLoan[Borrower] = false;
    }

    // Listings ---------------------------------------------------------------------------------

    function AutoList(address Collection, uint256 TokenId, address User) external{
        require(msg.sender == Treasury || msg.sender == LendContract, "Only Admin, Treasury or Lend Contract");

        if(msg.sender == Treasury){
            AddListingToCollection(Collection, TokenId, Listing(Treasury, Collection, TokenId));
            AddListingToUser(Treasury, Collection, TokenId, Listing(Treasury, Collection, TokenId));
        }
        else{
            AddListingToCollection(Collection, TokenId, Listing(User, Collection, TokenId));
            AddListingToUser(User, Collection, TokenId, Listing(User, Collection, TokenId));
        }

        ListedBool[Collection][TokenId] = true;
    }

    //auto delist, only treasury and lending contract can call this function, make it so that it cant break, because it will be called when removing a token from the treasury or lending contract
    function AutoDelist(address Collection, uint256 TokenId) external{
        require(msg.sender == Treasury || msg.sender == LendContract, "Only Admin, Treasury or Lend Contract");

        address Lister = ListingsByCollection[Collection][ListingsByCollectionIndex[Collection][TokenId]].Lister;

        RemoveListingFromCollection(Collection, TokenId);
        RemoveListingFromUser(Lister, Collection, TokenId);

        ListedBool[Collection][TokenId] = false;
    }

    //get list of all collections  
    function GetCollections() public view returns(address[] memory){
        return ListedCollections;
    }

    function IsListed(address Collection, uint256 TokenId) public view returns(bool){
        return ListedBool[Collection][TokenId];
    }

    function GetSingularListing(address _collection, uint256 _tokenId) public view returns(Listing memory){
        return ListingsByCollection[_collection][ListingsByCollectionIndex[_collection][_tokenId]];
    }

    function GetOwnershipByPurchase(address Collection, uint256 TokenId) public view returns(address){
        //TODO:Review, this will become the delegate cash
        // uint256 Expiry = AllLoans[AllLoansIndex[Collection][TokenId]].LoanEndTime;
        // if(Expiry > block.timestamp){
        //     return address(0);
        // }
        // else{
            return OwnershipByPurchase[Collection][TokenId];
        //}
    }

    function GetAllLoans() public view returns(LoanInfo[] storage){
            return AllLoans;
    }//TODO: FIX

    function GetUserLoans(address _user) public view returns(uint256[] memory){
        return AllUserLoans[_user];
    }

    function GetUserBorrows(address _user) public view returns(uint256[] memory){
        return AllUserBorrows[_user];
    }

    function GetUserListings(address user) public view returns (Listing[] memory){
        return ListingsByUser[user];
    }

    function GetListedCollectionWithPrices(address _collection) public view returns(Listing[] memory){
        return (ListingsByCollection[_collection]);
    }

    function GetAllLoans() public view returns (LoanInfo[] memory) {
        return AllLoans;
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

        ListingsByCollectionIndex[_collection][_tokenId] = 0;
    }

    function AddListingToUser(address _user, address _collection, uint256 _tokenId, Listing memory _listing) internal{
        ListingsByUser[_user].push(_listing);
        ListingsByUserIndex[_user][_collection][_tokenId] = ListingsByUser[_user].length - 1;
    }

    function RemoveListingFromUser(address _user, address _collection, uint256 _tokenId) internal{
        ListingsByUser[_user][ListingsByUserIndex[_user][_collection][_tokenId]] = ListingsByUser[_user][ListingsByUser[_user].length - 1];
        ListingsByUserIndex[_user][_collection][ListingsByUser[_user][ListingsByUserIndex[_user][_collection][_tokenId]].TokenId] = ListingsByUserIndex[_user][_collection][_tokenId];
        ListingsByUser[_user].pop();

        ListingsByUserIndex[_user][_collection][_tokenId] = 0;
    }

    //add loan to a borrower and a lender with just the loan address IN ONE function
    function AddLoanToBorrowerAndLender(address Borrower, address Lender, address Collection, uint256 ID) internal{
        LoanInfo memory _loan = LoanInfo(Collection, ID, Lender, Borrower);

        AllLoans.push(_loan);
        AllLoansIndex[Collection][ID] = AllLoans.length - 1;

        AllUserLoans[Lender].push(AllLoansIndex[Collection][ID]);
        AllUserLoansIndex[Lender][AllLoansIndex[Collection][ID]] = AllUserLoans[Lender].length - 1;

        AllUserBorrows[Borrower].push(AllLoansIndex[Collection][ID]);
        AllUserBorrowsIndex[Borrower][AllLoansIndex[Collection][ID]] = AllUserBorrows[Borrower].length - 1;
    }

    //remove loan from a borrower and a lender with just the loan address IN ONE function
    function RemoveLoanFromBorrowerAndLender(address Borrower, address Lender, address Collection, uint256 ID) internal {
        uint256 loanIndex = AllLoansIndex[Collection][ID];
        require(loanIndex < AllLoans.length, "Loan does not exist");

        // Remove from borrower's list
        uint256 borrowerLoanIndex = AllUserBorrowsIndex[Borrower][loanIndex];
        uint256 lastBorrowerLoanIndex = AllUserBorrows[Borrower].length - 1;
        
        if (borrowerLoanIndex != lastBorrowerLoanIndex) {
            uint256 lastBorrowerLoanID = AllUserBorrows[Borrower][lastBorrowerLoanIndex];
            AllUserBorrows[Borrower][borrowerLoanIndex] = lastBorrowerLoanID;
            AllUserBorrowsIndex[Borrower][lastBorrowerLoanID] = borrowerLoanIndex;
        }
        
        AllUserBorrows[Borrower].pop();
        delete AllUserBorrowsIndex[Borrower][loanIndex];

        // Remove from lender's list
        uint256 lenderLoanIndex = AllUserLoansIndex[Lender][loanIndex];
        uint256 lastLenderLoanIndex = AllUserLoans[Lender].length - 1;
        
        if (lenderLoanIndex != lastLenderLoanIndex) {
            uint256 lastLenderLoanID = AllUserLoans[Lender][lastLenderLoanIndex];
            AllUserLoans[Lender][lenderLoanIndex] = lastLenderLoanID;
            AllUserLoansIndex[Lender][lastLenderLoanID] = lenderLoanIndex;
        }

        AllUserLoans[Lender].pop();
        delete AllUserLoansIndex[Lender][loanIndex];

        // Remove from global loan list
        uint256 lastLoanIndex = AllLoans.length - 1;
        if (loanIndex != lastLoanIndex) {
            LoanInfo memory lastLoan = AllLoans[lastLoanIndex];
            AllLoans[loanIndex] = lastLoan;
            AllLoansIndex[lastLoan.Collection][lastLoan.ID] = loanIndex;
        }

        AllLoans.pop();
        delete AllLoansIndex[Collection][ID];
    }


    function ChangeFeeReceiver(address payable NewReceiver) public OnlyAdmin{
        FeeReceiver = NewReceiver;
    }

    function BlacklistUser(address payable user) public OnlyAdmin{
        Blacklisted[user] = true;
    }

    function ChangeRewardFee(uint256 NewFee) public OnlyAdmin{
        require(NewFee <= 1500, "Fee must be less than 15%");
        RewardFee = NewFee;
    }

    function ModifyCollection(address _collection, bool addRemove) public OnlyAdmin {
        if (addRemove) {
            ListedCollections.push(_collection);
            ListedCollectionsIndex[_collection] = ListedCollections.length - 1;
            ListedCollectionsMap[_collection] = true;
        } else {
            uint256 index = ListedCollectionsIndex[_collection];
            ListedCollections[index] = ListedCollections[ListedCollections.length - 1];
            ListedCollectionsIndex[ListedCollections[index]] = index;
            ListedCollections.pop();
            delete ListedCollectionsIndex[_collection];
            delete ListedCollectionsMap[_collection];
        }
    }
}

contract PlotsTreasury {
    // Variable and pointer Declarations
    address public immutable PlotsCoreContract;
    address public VLND;

    uint private InitialVLNDPrice = 500 * (10**12);
    bool public mintingPaused = false;

    // Mapping of all collections to an ether value
    mapping(address => uint256) public CollectionEtherValue;

    mapping(address => uint256[]) public AllTokensByCollection;
    mapping(address => mapping(uint256 => uint256)) public AllTokensByCollectionIndex;

    mapping(address => uint256) public UserAvgEntryPrice;

    modifier OnlyCore() {
        require(msg.sender == address(PlotsCoreContract), "Only Core");
        _;
    }

    // Only admin modifier using the core contract
    modifier OnlyAdmin() {
        require(PlotsCore(PlotsCoreContract).Admins(msg.sender) == true || msg.sender == PlotsCoreContract, "Only Admin");
        _;
    }

    modifier WhenMintingNotPaused() {
        require(!mintingPaused, "Minting is paused");
        _;
    }

    constructor(address _coreContract) {
        PlotsCoreContract = _coreContract;
    }

    function SetMintingPaused(bool _mintingPaused) public OnlyAdmin {
        mintingPaused = _mintingPaused;
    }

    function BuyVLND(uint256 minOut) public payable WhenMintingNotPaused {
        uint256 TotalValue = GetTotalValue() - msg.value;
        uint256 VLNDInCirculation = GetVLNDInCirculation();

        uint256 VLNDPrice;
        if (TotalValue > 0) {
            VLNDPrice = CalculateVLNDPrice(TotalValue, VLNDInCirculation);
        } else {
            VLNDPrice = 380000000000000; // 0.00038 ETH with 18 decimals
        }
        uint256 Amount = (msg.value * 10**18) / VLNDPrice;

        UserAvgEntryPrice[msg.sender] = ((UserAvgEntryPrice[msg.sender] * IERC20(VLND).balanceOf(msg.sender)) + (VLNDPrice * Amount)) / (IERC20(VLND).balanceOf(msg.sender) + Amount);

        require(Amount >= minOut, "Amount must be greater than or equal to minOut");

        IERC20(VLND).Mint(msg.sender, Amount);
    }
    
    function SellVLND(uint256 Amount, uint256 minOut) public WhenMintingNotPaused {
        uint256 VLNDPrice = GetVLNDPrice();
        uint256 Value = (Amount * VLNDPrice) / 10 ** 18;

        require((address(this).balance - PlotsCore(PlotsCoreContract).LockedValue()) >= ((GetTotalValue() * 5) / 100), "Not enough ether in treasury, must leave 5%");
        require(Value >= minOut, "Value must be greater than or equal to minOut");

        IERC20(VLND).transferFrom(msg.sender, address(this), Amount);
        IERC20(VLND).Burn(Amount);
        payable(msg.sender).transfer(Value);
    }

    function DepositNFT(address Collection, uint256 TokenId) public OnlyAdmin {
        require(IERC721(Collection).ownerOf(TokenId) == msg.sender, "Not owner of token");
        IERC721(Collection).transferFrom(msg.sender, address(this), TokenId);

        AddTokenToCollection(Collection, TokenId);

        PlotsCore(PlotsCoreContract).AutoList(Collection, TokenId, address(this));
    }

    function DepositNFTs(address[] memory Collections, uint256[] memory TokenIds) public OnlyAdmin {
        require(Collections.length == TokenIds.length, "Arrays not same length");
        for (uint256 i = 0; i < Collections.length; i++) {
            DepositNFT(Collections[i], TokenIds[i]);
        }
    }

    function WithdrawNFT(address Collection, uint256 TokenId) public OnlyAdmin {
        require(IERC721(Collection).ownerOf(TokenId) == address(this), "Not owner of token");
        IERC721(Collection).transferFrom(address(this), msg.sender, TokenId);

        PlotsCore(PlotsCoreContract).AutoDelist(Collection, TokenId);

        RemoveTokenFromCollection(Collection, TokenId);
    }

    function WithdrawNFTs(address[] memory Collections, uint256[] memory TokenIds) public OnlyAdmin {
        require(Collections.length == TokenIds.length, "Arrays not same length");
        for (uint256 i = 0; i < Collections.length; i++) {
            WithdrawNFT(Collections[i], TokenIds[i]);
        }
    }

    function SendEther(address payable Recipient, uint256 Amount) public OnlyAdmin {
        require((address(this).balance - PlotsCore(PlotsCoreContract).LockedValue()) >= Amount, "Not enough ether in treasury");
        Recipient.transfer(Amount);
    }

    function SendERC20(address Token, address Recipient, uint256 Amount) public OnlyAdmin {
        IERC20(Token).transfer(Recipient, Amount);
    }

    // Allow admin to set ether value for multiple collections at once, with an array with the collections and an array with the ether values
    function SetCollectionEtherValue(address[] memory Collections, uint256[] memory EtherValues) public OnlyAdmin {
        require(Collections.length == EtherValues.length, "Arrays not same length");
        for (uint256 i = 0; i < Collections.length; i++) {
            require(PlotsCore(PlotsCoreContract).ListedCollectionsMap(Collections[i]) == true, "Collection not listed");
            CollectionEtherValue[Collections[i]] = EtherValues[i];
        }
    }

    function SetVLND(address _vlnd) public OnlyAdmin {
        require(VLND == address(0), "VLND already set");
        VLND = _vlnd;
    }

    // Internals

    // Add token to collection array
    function AddTokenToCollection(address Collection, uint256 TokenId) internal {
        AllTokensByCollection[Collection].push(TokenId);
        AllTokensByCollectionIndex[Collection][TokenId] = AllTokensByCollection[Collection].length - 1;
    }

    // Remove token from collection array
    function RemoveTokenFromCollection(address Collection, uint256 TokenId) internal {
        AllTokensByCollection[Collection][AllTokensByCollectionIndex[Collection][TokenId]] = AllTokensByCollection[Collection][AllTokensByCollection[Collection].length - 1];
        AllTokensByCollectionIndex[Collection][AllTokensByCollection[Collection][AllTokensByCollectionIndex[Collection][TokenId]]] = AllTokensByCollectionIndex[Collection][TokenId];
        AllTokensByCollection[Collection].pop();
    }

    // Views 

    // Get total value of the treasury by looping through all collections and getting the locked value
    function GetTotalValue() public view returns (uint256) {
        uint256 TotalValue;
        address[] memory ListedCollections = PlotsCore(PlotsCoreContract).GetCollections();  
        for (uint256 i = 0; i < ListedCollections.length; i++) {
            TotalValue += CollectionEtherValue[ListedCollections[i]] * AllTokensByCollection[ListedCollections[i]].length;
        }
        TotalValue += (address(this).balance - PlotsCore(PlotsCoreContract).LockedValue());
        return TotalValue;
    }

    function GetCollectionEtherValue(address Collection) public view returns (uint256) {
        return CollectionEtherValue[Collection];
    }

    // Get the price of VLND in ether by dividing the total value of the treasury by the circulating supply of VLND, which is all VLND minus the VLND in the treasury, to get an exchange rate and avoid overflow, get the price of an entire VLND and not just one wei
    function GetVLNDPrice() public view returns (uint256) {
        uint256 TotalValue = GetTotalValue();
        uint256 VLNDInCirculation = GetVLNDInCirculation();

        if (TotalValue == 0) {
            return 380000000000000;
        } else {
            return CalculateVLNDPrice(TotalValue, VLNDInCirculation);
        }
    }

    // Get VLND in circulation by subtracting the VLND in the treasury from the total supply
    function GetVLNDInCirculation() public view returns (uint256) {
        return IERC20(VLND).totalSupply();
    }

    function GetUserAverageEntryPrice(address User) public view returns (uint256) {
        return UserAvgEntryPrice[User];
    }
    
    function CalculateVLNDPrice(uint256 TotalValue, uint256 VLNDSupply) internal view returns (uint256) {
        return Calculations.CalculateVLNDPrice(TotalValue, VLNDSupply, InitialVLNDPrice);
    }

    receive() external payable {}
}

contract PlotsLend {
    //Variable and pointer Declarations
    address public immutable PlotsCoreContract;

    constructor(address _coreContract){
        PlotsCoreContract = _coreContract;
    }

    struct Token{
        address Collection;
        uint256 TokenId;
    }

    modifier OnlyCore(){
        require(msg.sender == address(PlotsCoreContract), "Only Core");
        _;
    }

    mapping(address => mapping(uint256 => address)) public TokenDepositor;

    //all deposited tokens array mapping
    mapping(address => Token[]) public AllUserTokens;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public AllUserTokensIndex;

    //allow a user to deposit a token into the lending contract from any collection that is listed on the core contract
    function DepositToken(address Collection, uint256 TokenId) public{
        require(IERC721(Collection).ownerOf(TokenId) == msg.sender, "Not owner of token");
        IERC721(Collection).transferFrom(msg.sender, address(this), TokenId);

        TokenDepositor[Collection][TokenId] = msg.sender;
        AllUserTokens[msg.sender].push(Token(Collection, TokenId));
        AllUserTokensIndex[msg.sender][Collection][TokenId] = AllUserTokens[msg.sender].length - 1;

        PlotsCore(PlotsCoreContract).AutoList(Collection, TokenId, msg.sender);
    }

    function DepositTokens(address[] memory Collections, uint256[] memory TokenIds) public{
        require(Collections.length == TokenIds.length, "Arrays not same length");
        for(uint256 i = 0; i < Collections.length; i++){
            DepositToken(Collections[i], TokenIds[i]);
        }
    }

    function WithdrawToken(address Collection, uint256 TokenId) public {
        require(TokenDepositor[Collection][TokenId] == msg.sender, "Not owner of token");

        PlotsCore(PlotsCoreContract).AutoDelist(Collection, TokenId);

        IERC721(Collection).transferFrom(address(this), msg.sender, TokenId);

        TokenDepositor[Collection][TokenId] = address(0);

        uint256 lastIndex = AllUserTokens[msg.sender].length - 1;
        uint256 currentIndex = AllUserTokensIndex[msg.sender][Collection][TokenId];

        if (currentIndex != lastIndex) {
            AllUserTokens[msg.sender][currentIndex] = AllUserTokens[msg.sender][lastIndex];
            AllUserTokensIndex[msg.sender][Collection][AllUserTokens[msg.sender][currentIndex].TokenId] = currentIndex;
        }

        AllUserTokens[msg.sender].pop();
        AllUserTokensIndex[msg.sender][Collection][TokenId] = 0;
    }
    
    //create an autowithdraw to be called on closeloan

    function Autowithdraw(address Collection, uint256 TokenId) public OnlyCore{
        require(TokenDepositor[Collection][TokenId] != address(0), "Token not deposited");
        IERC721(Collection).transferFrom(address(this), TokenDepositor[Collection][TokenId], TokenId);
        TokenDepositor[Collection][TokenId] = address(0);
    }

    function WithdrawTokens(address[] memory Collections, uint256[] memory TokenIds) public{
        require(Collections.length == TokenIds.length, "Arrays not same length");
        for(uint256 i = 0; i < Collections.length; i++){
            WithdrawToken(Collections[i], TokenIds[i]);
        }
    }

    //View Functions 

    function GetUserTokens(address _user) public view returns(Token[] memory UserTokens, bool[] memory IsListed, bool[] memory InLoan){
        Token[] memory userTokens = AllUserTokens[_user];
        bool[] memory isListed = new bool[](userTokens.length);
        bool[] memory inLoan = new bool[](userTokens.length);
        for(uint256 i = 0; i < userTokens.length; i++){
            isListed[i] = PlotsCore(PlotsCoreContract).IsListed(userTokens[i].Collection, userTokens[i].TokenId);
            inLoan[i] = PlotsCore(PlotsCoreContract).InLoanBool(userTokens[i].Collection, userTokens[i].TokenId);
        }
        return (userTokens, isListed, inLoan);
    }

    function GetTokenDepositor(address Collection, uint256 TokenId) public view returns(address){
        return TokenDepositor[Collection][TokenId];
    }
}


library Calculations {

    function CalculateVLNDPrice(uint256 TotalValue, uint256 VLNDSupply, uint256 InitialVLNDPrice) internal pure returns(uint256){
        if (VLNDSupply == 0){
            return InitialVLNDPrice;
        }
        else {
            return TotalValue / (VLNDSupply / 10 ** 18);
        }
    }
}

interface IERC20 {
  function balanceOf(address owner) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 value) external returns (bool);
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool); 
  function totalSupply() external view returns (uint256);
  function Mint(address _MintTo, uint256 _MintAmount) external;
  function Burn(uint256 _BurnAmount) external;
}

interface IERC721 {
    function balanceOf(address _owner) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external payable;
    function transferFrom(address _from, address _to, uint256 _tokenId) external payable;
    function approve(address _approved, uint256 _tokenId) external payable;
    function setApprovalForAll(address _operator, bool _approved) external;
    function getApproved(uint256 _tokenId) external view returns (address);
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}