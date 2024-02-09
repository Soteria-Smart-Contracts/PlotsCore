// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.19;

contract PlotsCoreV1 {
    //Variable and pointer Declarations
    address payable public Treasury;
    address payable public FeeReceiver;
    uint256 public RewardFee;
    uint256 public LockedValue;
    address public LendContract;
    address[] public ListedCollections;
    mapping(address => bool) public ListedCollectionsMap;
    mapping(address => uint256) public ListedCollectionsIndex;
    address[] public AvailableLoanContracts;
    mapping(address => uint256) public AvailableLoanContractsIndex;
    mapping(address => mapping(uint256 => address)) public LoanContractByToken;
    mapping(address => bool) public IsLoanContract;
    mapping(address => mapping(address => uint256)) BorrowerRewardPayoutTracker;
    mapping(address => mapping(address => uint256)) OwnerRewardPayoutTracker;
    mapping(address => address[]) public RewardTokenClaimants;
    mapping(address => Payout[]) public RewardTokenPayouts; 

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

    struct Payout{
        address Token;
        uint256 Amount;
        uint256 Time;
    }

    mapping(address => bool) public Admins;
    modifier OnlyAdmin(){
        require(Admins[msg.sender], "Only Admin");
        _;
    }

    mapping(address => mapping(uint256 => address)) public OwnershipByPurchase;

    mapping(address => Listing[]) public ListingsByCollection;
    mapping(address => mapping(uint256 => uint256)) public ListingsByCollectionIndex;
    mapping(address => mapping(uint256 => bool)) public ListedBool;
    mapping(address => Listing[]) public ListingsByUser;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public ListingsByUserIndex;

    mapping(address => address[]) public AllUserLoans; //Outgoing loans
    mapping(address => mapping(address => uint256)) public AllUserLoansIndex;

    mapping(address => address[]) public AllUserBorrows; //Incoming loans
    mapping(address => mapping(address => uint256)) public AllUserBorrowsIndex;


    constructor(address [] memory _admins, address payable _feeReceiver){
        Treasury = payable(new PlotsTreasuryV1());
        LendContract = address(new PlotsLendV1());
        FeeReceiver = _feeReceiver;

        for(uint256 i = 0; i < _admins.length; i++){
            Admins[_admins[i]] = true;
        }
        Admins[msg.sender] = true;
        Admins[Treasury] = true;
    }


    function BorrowToken(address Collection, uint256 TokenId, LengthOption Duration, OwnershipPercent Ownership) public payable {
        require(ListedCollectionsMap[Collection] == true, "Collection N/Listed");
        uint256 TokenIndex = ListingsByCollectionIndex[Collection][TokenId];
        require(ListingsByCollection[Collection][TokenIndex].Lister != address(0), "Token N/Listed");

        address LoanContract;
        if(AvailableLoanContracts.length > 0){
            LoanContract = AvailableLoanContracts[AvailableLoanContracts.length - 1];
            AvailableLoanContractsIndex[LoanContract] = 0;
            AvailableLoanContracts.pop();
        }
        else{
            LoanContract = address(new NFTLoan());
            IsLoanContract[LoanContract] = true;
        }

        uint256 TokenValue = 0;
        uint256 DurationUnix = (uint8(Duration) + 1) * 60; //TODO: CHANGE LEGNTH BACK TO 90 DAYS BEFORE MAINNET DEPLOYMENT
        address Origin;
        
        if(ListingsByCollection[Collection][TokenIndex].OwnershipOption == ListingType.Ownership){
            TokenValue = PlotsTreasuryV1(Treasury).GetTokenValueFloorAdjusted(Collection, TokenId);
            uint256 Fee = (TokenValue * 20) / 1000;
            uint256 BorrowCost = Fee;
            if(Ownership == OwnershipPercent.Ten){
                BorrowCost += (TokenValue * 10) / 100;
            }
            else if(Ownership == OwnershipPercent.TwentyFive){
                BorrowCost += (TokenValue * 25) / 100;
            }
            require(msg.value >= BorrowCost, "Not enough ether sent");
            PlotsTreasuryV1(Treasury).SendToLoan(LoanContract, Collection, TokenId);

            FeeReceiver.transfer(Fee);
            payable(Treasury).transfer(address(this).balance);
            LockedValue += BorrowCost - Fee;
            Origin = Treasury;
        }
        else if(PlotsLendV1(LendContract).GetTokenLocation(Collection, TokenId) == LendContract){
            require(Ownership == OwnershipPercent.Zero);
            PlotsLendV1(LendContract).SendToLoan(LoanContract, Collection, TokenId);
            RemoveListingFromUser(ListingsByCollection[Collection][TokenIndex].Lister, Collection, TokenId);
            Origin = LendContract;
        }
        else if(ERC721(Collection).ownerOf(TokenId) == Treasury){
            require(Ownership == OwnershipPercent.Zero);
            PlotsTreasuryV1(Treasury).SendToLoan(LoanContract, Collection, TokenId);
            Origin = Treasury;
        }
        else{
            revert("Invalid token");
        }

        LoanContractByToken[Collection][TokenId] = LoanContract;
        AddLoanToBorrowerAndLender(msg.sender, ListingsByCollection[Collection][TokenIndex].Lister, LoanContract);
        NFTLoan(LoanContract).BeginLoan(Ownership, ListingsByCollection[Collection][TokenIndex].Lister , msg.sender, Collection, TokenId, DurationUnix, TokenValue, Origin);
        RemoveListingFromCollection(Collection, TokenId);
        OwnershipByPurchase[Collection][TokenId] = msg.sender;
        ListedBool[Collection][TokenId] = false;
    }

    function CloseLoan(address LoanContract, bool relist) public{
        require(
            IsLoanContract[LoanContract] == true &&
            NFTLoan(LoanContract).Borrower() == msg.sender || NFTLoan(LoanContract).Owner() == msg.sender || Admins[msg.sender] &&
            NFTLoan(LoanContract).LoanEndTime() <= block.timestamp || Admins[msg.sender] || NFTLoan(LoanContract).Borrower() == msg.sender &&
            NFTLoan(LoanContract).Active(),
            "Invalid loan"
        );

        address Collection = NFTLoan(LoanContract).TokenCollection();
        uint256 TokenId = NFTLoan(LoanContract).TokenID();
        address Borrower = NFTLoan(LoanContract).Borrower();
        address Lender = NFTLoan(LoanContract).Owner();
        address Origin = NFTLoan(LoanContract).Origin();
        uint256 OwnershipPercentage;
        uint256 CollateralValue;

        if(NFTLoan(LoanContract).OwnershipType() == OwnershipPercent.Ten){
            OwnershipPercentage = 10;
        }
        else if(NFTLoan(LoanContract).OwnershipType() == OwnershipPercent.TwentyFive){
            OwnershipPercentage = 25;
        }

        if(Origin == LendContract){
            OwnershipPercentage = 0;
            CollateralValue = 0;
            NFTLoan(LoanContract).EndLoan();
            PlotsLendV1(LendContract).ReturnedFromLoan(Collection, TokenId);
        }
        else if(Origin == Treasury && NFTLoan(LoanContract).OwnershipType() != OwnershipPercent.Zero){
            CollateralValue = (PlotsTreasuryV1(Treasury).GetTokenValueFloorAdjusted(Collection, TokenId) * OwnershipPercentage) / 100;
            LockedValue -= NFTLoan(LoanContract).InitialValue() * OwnershipPercentage / 100;
            NFTLoan(LoanContract).EndLoan();
            PlotsTreasuryV1(Treasury).ReturnedFromLoan(Collection, TokenId);
            PlotsTreasuryV1(Treasury).SendEther(payable(Borrower), CollateralValue);
        }
        else if(Origin == Treasury && NFTLoan(LoanContract).OwnershipType() == OwnershipPercent.Zero){
            NFTLoan(LoanContract).EndLoan();
            PlotsTreasuryV1(Treasury).ReturnedFromLoan(Collection, TokenId);
        }
        else{
            revert("Invalid loan");
        }

        LoanContractByToken[Collection][TokenId] = address(0);
        OwnershipByPurchase[Collection][TokenId] = address(0);
        AvailableLoanContracts.push(LoanContract);
        AvailableLoanContractsIndex[LoanContract] = AvailableLoanContracts.length - 1;
        RemoveLoanFromBorrowerAndLender(Borrower, Lender, LoanContract);

        if(relist == true){
            require(Lender == msg.sender || Lender == Treasury, "Not owner of token");
            AddListingToCollection(Collection, TokenId, Listing(Lender, Collection, TokenId, ListingType.Usage));
            if(Lender != Treasury){
                AddListingToUser(Lender, Collection, TokenId, Listing(Lender, Collection, TokenId, ListingType.Usage));
            }
            ListedBool[Collection][TokenId] = true;
        }
    }

    function RenewLoan(address LoanContract, LengthOption Duration) public payable {
        require(NFTLoan(LoanContract).OwnershipType() != OwnershipPercent.Zero && NFTLoan(LoanContract).Borrower() == msg.sender && NFTLoan(LoanContract).Active(), "Invalid loan conditions");
        uint256 DurationUnix = (uint8(Duration) + 1) * 60;
        NFTLoan(LoanContract).RenewLoan(DurationUnix);
    }

    // Listings ---------------------------------------------------------------------------------

    function ListToken(address Collection, uint256 TokenId) public{
        require(ListedCollectionsMap[Collection] == true && ListedBool[Collection][TokenId] == false, "Collection not listed or token already listed");
        

        if(Admins[msg.sender]){
            require(ERC721(Collection).ownerOf(TokenId) == Treasury, "Token not owned by treasury");
            AddListingToCollection(Collection, TokenId, Listing(Treasury, Collection, TokenId, ListingType.Ownership));

        }
        else{
            require(ERC721(Collection).ownerOf(TokenId) == LendContract && PlotsLendV1(LendContract).GetTokenDepositor(Collection, TokenId) == msg.sender, "Invalid ownership or token not owned by lending contract");
            AddListingToCollection(Collection, TokenId, Listing(msg.sender, Collection, TokenId, ListingType.Usage));
            AddListingToUser(msg.sender, Collection, TokenId, Listing(msg.sender, Collection, TokenId, ListingType.Usage));
        }

        ListedBool[Collection][TokenId] = true;
    }

    function DelistToken(address Collection, uint256 TokenId) public{
        require(ListedCollectionsMap[Collection] == true && ListingsByCollection[Collection][ListingsByCollectionIndex[Collection][TokenId]].Lister != address(0), "Collection not listed or token not listed");
    
        if(ListingsByCollection[Collection][ListingsByCollectionIndex[Collection][TokenId]].Lister == Treasury){
            require(Admins[msg.sender], "Only Admin");
        }
        else{
            require(ListingsByCollection[Collection][ListingsByCollectionIndex[Collection][TokenId]].Lister == msg.sender, "Not owner of listing");
            RemoveListingFromUser(msg.sender, Collection, TokenId);
        }

        RemoveListingFromCollection(Collection, TokenId);
        ListedBool[Collection][TokenId] = false;
    }

    function ManageTokens(address[] memory Collections, uint256[] memory TokenIds, bool isList) public {
        require(Collections.length == TokenIds.length, "Arrays not same length");
        for(uint256 i = 0; i < Collections.length; i++){
            if (isList) {
                ListToken(Collections[i], TokenIds[i]);
            } else {
                DelistToken(Collections[i], TokenIds[i]);
            }
        }
    }

    //claim multiple rewards at once function, input an array of loan contracts and reward tokens
    function ClaimRewards(address[] memory LoanContracts, address[] memory RewardTokens) public{
        require(LoanContracts.length == RewardTokens.length, "Arrays not same length");
        for(uint256 i = 0; i < LoanContracts.length; i++){
            NFTLoan(LoanContracts[i]).DisperseRewards(RewardTokens[i]);
        }
    }

    //get list of all collections  
    function GetCollections() public view returns(address[] memory){
        return ListedCollections;
    }

    function GetCollectionListings(address _collection) public view returns(Listing[] memory){
        return ListingsByCollection[_collection];
    }

    function IsListed(address Collection, uint256 TokenId) public view returns(bool){
        return ListedBool[Collection][TokenId];
    }

    function GetSingularListing(address _collection, uint256 _tokenId) public view returns(Listing memory){
        return ListingsByCollection[_collection][ListingsByCollectionIndex[_collection][_tokenId]];
    }

    function GetOwnershipByPurchase(address Collection, uint256 TokenId) public view returns(address){
        uint256 Expiry = NFTLoan(LoanContractByToken[Collection][TokenId]).LoanEndTime();
        if(Expiry > block.timestamp){
            return address(0);
        }
        else{
            return OwnershipByPurchase[Collection][TokenId];
        }
    }

    function GetRewardTokenClaimants(address Token) public view returns(address[] memory){
        return RewardTokenClaimants[Token];
    }

    function GetRewardTokenPayouts(address User) public view returns(Payout[] memory){
        return RewardTokenPayouts[User];
    }
    
    function GetUserLoans(address _user) public view returns(address[] memory){
        return AllUserLoans[_user];
    }

    function GetUserBorrows(address _user) public view returns(address[] memory){
        return AllUserBorrows[_user];
    }

    function GetUserListings(address user) public view returns (Listing[] memory){
        return ListingsByUser[user];
    }

    function GetListedCollectionWithPrices(address _collection) public view returns(Listing[] memory, uint256[] memory Prices){
        uint256[] memory _prices = new uint256[](ListingsByCollection[_collection].length);
        for(uint256 i = 0; i < ListingsByCollection[_collection].length; i++){
            if(ListingsByCollection[_collection][i].OwnershipOption == ListingType.Ownership){
                _prices[i] = PlotsTreasuryV1(Treasury).GetTokenValueFloorAdjusted(_collection, ListingsByCollection[_collection][i].TokenId);
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
    function AddLoanToBorrowerAndLender(address Borrower, address Lender, address _loan) internal{
        AllUserLoans[Lender].push(_loan);
        AllUserLoansIndex[Lender][_loan] = AllUserLoans[Lender].length - 1;

        AllUserBorrows[Borrower].push(_loan);
        AllUserBorrowsIndex[Borrower][_loan] = AllUserBorrows[Borrower].length - 1;
    }

    //remove loan from a borrower and a lender with just the loan address IN ONE function
    function RemoveLoanFromBorrowerAndLender(address Borrower, address Lender, address _loan) internal{
        AllUserLoans[Lender][AllUserLoansIndex[Lender][_loan]] = AllUserLoans[Lender][AllUserLoans[Lender].length - 1];
        AllUserLoansIndex[Lender][AllUserLoans[Lender][AllUserLoansIndex[Lender][_loan]]] = AllUserLoansIndex[Lender][_loan];
        AllUserLoans[Lender].pop();
        AllUserLoansIndex[Lender][_loan] = 0;

        AllUserBorrows[Borrower][AllUserBorrowsIndex[Borrower][_loan]] = AllUserBorrows[Borrower][AllUserBorrows[Borrower].length - 1];
        AllUserBorrowsIndex[Borrower][AllUserBorrows[Borrower][AllUserBorrowsIndex[Borrower][_loan]]] = AllUserBorrowsIndex[Borrower][_loan];
        AllUserBorrows[Borrower].pop();
        AllUserBorrowsIndex[Borrower][_loan] = 0;
    }

    function ChangeFeeReceiver(address payable NewReceiver) public OnlyAdmin{
        FeeReceiver = NewReceiver;
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

    //function update payout tracker only callable by loan contracts (isloancontract mapping), input for a user and a token and amount
    function UpdateBorrowerPayoutTracker(address User, address Token, uint256 Amount) public{
        require(IsLoanContract[msg.sender] == true, "Only Loan Contracts");

        if(BorrowerRewardPayoutTracker[User][Token] == 0){
            RewardTokenClaimants[Token].push(User);
        }

        RewardTokenPayouts[User].push(Payout(Token, Amount, block.timestamp));

        BorrowerRewardPayoutTracker[User][Token] += Amount;
    }

    function UpdateOwnerPayoutTracker(address User, address Token, uint256 Amount) public{
        require(IsLoanContract[msg.sender] == true, "Only Loan Contracts");

        if(OwnerRewardPayoutTracker[User][Token] == 0){
            RewardTokenClaimants[Token].push(User);
        }

        RewardTokenPayouts[User].push(Payout(Token, Amount, block.timestamp));

        OwnerRewardPayoutTracker[User][Token] += Amount;
    }
}

contract PlotsTreasuryV1{
    //Variable and pointer Declarations
    address public PlotsCoreContract;
    address public VLND;

    //mapping of all collections to a floor price
    mapping(address => uint256) public CollectionFloorPrice;
    mapping(address => mapping(uint256 => uint256)) public TokenFloorFactor;
    mapping(address => mapping(uint256 => address)) public TokenLocation;

    mapping(address => uint256[]) public AllTokensByCollection;
    mapping(address => mapping(uint256 => uint256)) public AllTokensByCollectionIndex;

    mapping(address => uint256) public CollectionLockedValue;


    modifier OnlyCore(){
        require(msg.sender == address(PlotsCoreContract), "Only Core");
        _;
    }

    //only admin modifier using the core contract
    modifier OnlyAdmin(){
        require(PlotsCoreV1(PlotsCoreContract).Admins(msg.sender) == true || msg.sender == PlotsCoreContract, "Only Admin");
        _;
    }

    constructor(){
        PlotsCoreContract = msg.sender;
    }

    function BuyVLND(uint256 minOut) public payable{
        uint256 TotalValue = GetTotalValue() - msg.value;
        uint256 VLNDInCirculation = GetVLNDInCirculation();
        VLNDInCirculation = VLNDInCirculation / 10 ** 18;

        uint256 VLNDPrice = TotalValue / VLNDInCirculation;
        uint256 Amount = (msg.value * 10**18) / VLNDPrice;

        require(Amount >= minOut, "Amount must be greater than or equal to minOut");

        ERC20(VLND).transfer(msg.sender, Amount);
    }
    
    function SellVLND(uint256 Amount, uint256 minOut) public {
        uint256 VLNDPrice = GetVLNDPrice();
        uint256 Value = (Amount * VLNDPrice) / 10 ** 18;

        require(((address(this).balance - PlotsCoreV1(PlotsCoreContract).LockedValue()) - Value) >= ((GetTotalValue() * 5) / 100), "Not enough ether in treasury, must leave 5%");
        require(Value >= minOut, "Value must be greater than or equal to minOut");

        ERC20(VLND).transferFrom(msg.sender, address(this), Amount);
        payable(msg.sender).transfer(Value);
    }

    function DepositNFT(address Collection, uint256 TokenId, uint256 EtherCost) public OnlyAdmin {
        require(ERC721(Collection).ownerOf(TokenId) == msg.sender, "Not owner of token");
        ERC721(Collection).transferFrom(msg.sender, address(this), TokenId);

        TokenFloorFactor[Collection][TokenId] = ((EtherCost * 1000) / CollectionFloorPrice[Collection]);
        TokenLocation[Collection][TokenId] = address(this);

        AddTokenToCollection(Collection, TokenId);
        CollectionLockedValue[Collection] += EtherCost;
    }

    function DepositNFTs(address[] memory Collections, uint256[] memory TokenIds, uint256[] memory EtherCosts) public OnlyAdmin {
        require(Collections.length == TokenIds.length && Collections.length == EtherCosts.length, "Arrays not same length");
        for(uint256 i = 0; i < Collections.length; i++){
            DepositNFT(Collections[i], TokenIds[i], EtherCosts[i]);
        }
    }

    function WithdrawNFT(address Collection, uint256 TokenId) public OnlyAdmin {
        require(ERC721(Collection).ownerOf(TokenId) == address(this), "Not owner of token");
        ERC721(Collection).transferFrom(address(this), msg.sender, TokenId);

        //check if listed, if so remove listing
        if(PlotsCoreV1(PlotsCoreContract).IsListed(Collection, TokenId) == true){
            PlotsCoreV1(PlotsCoreContract).DelistToken(Collection, TokenId);
        }

        CollectionLockedValue[Collection] -= GetTokenValueFloorAdjusted(Collection, TokenId);
        TokenFloorFactor[Collection][TokenId] = 0;
        RemoveTokenFromCollection(Collection, TokenId);
    }

    function WithdrawNFTs(address[] memory Collections, uint256[] memory TokenIds) public OnlyAdmin {
        require(Collections.length == TokenIds.length, "Arrays not same length");
        for(uint256 i = 0; i < Collections.length; i++){
            WithdrawNFT(Collections[i], TokenIds[i]);
        }
    }

    function SendEther(address payable Recipient, uint256 Amount) public OnlyAdmin {
        require((address(this).balance - PlotsCoreV1(PlotsCoreContract).LockedValue()) >= Amount, "Not enough ether in treasury");
        Recipient.transfer(Amount);
    }

    function SendERC20(address Token, address Recipient, uint256 Amount) public OnlyAdmin {
        ERC20(Token).transfer(Recipient, Amount);
    }

    //allow admin to set floor price for multiple collections at once, with an array with the collections and an array with the floor prices
    function SetFloorPrice(address[] memory Collections, uint256[] memory FloorPrices) public OnlyAdmin{
        require(Collections.length == FloorPrices.length, "Arrays not same length");
        for(uint256 i = 0; i < Collections.length; i++){
            require(PlotsCoreV1(PlotsCoreContract).ListedCollectionsMap(Collections[i]) == true, "Collection not listed");
            CollectionFloorPrice[Collections[i]] = FloorPrices[i];

            CollectionLockedValue[Collections[i]] = 0;
            for(uint256 j = 0; j < AllTokensByCollection[Collections[i]].length; j++){
                CollectionLockedValue[Collections[i]] += GetTokenValueFloorAdjusted(Collections[i], AllTokensByCollection[Collections[i]][j]);
            }
        }
    }

    function SetVLND(address _vlnd) public OnlyAdmin{
        require(VLND == address(0), "VLND already set");
        VLND = _vlnd;
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

    //internals

    //add token to collection array
    function AddTokenToCollection(address Collection, uint256 TokenId) internal{
        AllTokensByCollection[Collection].push(TokenId);
        AllTokensByCollectionIndex[Collection][TokenId] = AllTokensByCollection[Collection].length - 1;
    }

    //remove token from collection array

    function RemoveTokenFromCollection(address Collection, uint256 TokenId) internal{
        AllTokensByCollection[Collection][AllTokensByCollectionIndex[Collection][TokenId]] = AllTokensByCollection[Collection][AllTokensByCollection[Collection].length - 1];
        AllTokensByCollectionIndex[Collection][AllTokensByCollection[Collection][AllTokensByCollectionIndex[Collection][TokenId]]] = AllTokensByCollectionIndex[Collection][TokenId];
        AllTokensByCollection[Collection].pop();
    }

    //views 

    //get total value of the treasury by looping through all collections and getting the locked value
    function GetTotalValue() public view returns(uint256){
        uint256 TotalValue;
        address[] memory ListedCollections = PlotsCoreV1(PlotsCoreContract).GetCollections();  
        for(uint256 i = 0; i < ListedCollections.length; i++){
            TotalValue += CollectionLockedValue[ListedCollections[i]];
        }
        TotalValue += (address(this).balance - PlotsCoreV1(PlotsCoreContract).LockedValue());
        return TotalValue;
    }

    function GetFloorPrice(address Collection) public view returns(uint256){
        return CollectionFloorPrice[Collection];
    }

    function GetFloorFactor(address Collection, uint256 TokenId) public view returns(uint256){
        return TokenFloorFactor[Collection][TokenId];
    }

    function GetTokenValueFloorAdjusted(address Collection, uint256 TokenId) public view returns(uint256){
        return((CollectionFloorPrice[Collection] * TokenFloorFactor[Collection][TokenId]) / 1000);
    }

    //get the price of VLND in ether by dividing the total value of the treasury by the circulating supply of vlnd whcih is all vlnd minus the vlnd in the treasury, to get an exchange rate and avoid overflow, get the price of an entire vlnd and not just one wei
    function GetVLNDPrice() public view returns(uint256){
        uint256 TotalValue = GetTotalValue();
        uint256 VLNDInCirculation = GetVLNDInCirculation();
        VLNDInCirculation = VLNDInCirculation / 10 ** 18;

        return(TotalValue / VLNDInCirculation);
    }

    //get vlnd in circulation by subtracting the vlnd in the treasury from the total supply
    function GetVLNDInCirculation() public view returns(uint256){
        return(ERC20(VLND).totalSupply() - ERC20(VLND).balanceOf(address(this)));
    }
    
    receive() external payable{}

}

contract PlotsLendV1{
    //Variable and pointer Declarations
    address public PlotsCoreContract;

    constructor(){
        PlotsCoreContract = msg.sender;
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

    function DepositTokens(address[] memory Collections, uint256[] memory TokenIds) public{
        require(Collections.length == TokenIds.length, "Arrays not same length");
        for(uint256 i = 0; i < Collections.length; i++){
            DepositToken(Collections[i], TokenIds[i]);
        }
    }

    function WithdrawToken(address Collection, uint256 TokenId) public{
        require(TokenDepositor[Collection][TokenId] == msg.sender, "Not owner of token");
        require(TokenLocation[Collection][TokenId] == address(this), "Token not in lending contract");
        require(!PlotsCoreV1(PlotsCoreContract).IsListed(Collection, TokenId), "Token should not be listed");

        ERC721(Collection).transferFrom(address(this), msg.sender, TokenId);

        TokenDepositor[Collection][TokenId] = address(0);
        TokenLocation[Collection][TokenId] = address(0);

        uint256 lastIndex = AllUserTokens[msg.sender].length - 1;
        uint256 currentIndex = AllUserTokensIndex[msg.sender][Collection][TokenId];

        if(currentIndex != lastIndex) {
            AllUserTokens[msg.sender][currentIndex] = AllUserTokens[msg.sender][lastIndex];
            AllUserTokensIndex[msg.sender][Collection][AllUserTokens[msg.sender][currentIndex].TokenId] = currentIndex;
        }
        AllUserTokens[msg.sender].pop();
        AllUserTokensIndex[msg.sender][Collection][TokenId] = 0;
    }

    function WithdrawTokens(address[] memory Collections, uint256[] memory TokenIds) public{
        require(Collections.length == TokenIds.length, "Arrays not same length");
        for(uint256 i = 0; i < Collections.length; i++){
            WithdrawToken(Collections[i], TokenIds[i]);
        }
    }

    //send and return from loan functions

    function SendToLoan(address LoanContract, address Collection, uint256 TokenID) external OnlyCore{
        ERC721(Collection).transferFrom(address(this), LoanContract, TokenID);

        TokenLocation[Collection][TokenID] = LoanContract;
    }

    function ReturnedFromLoan(address Collection, uint256 TokenID) external OnlyCore{        
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
    address public Origin;
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

    function BeginLoan(PlotsCoreV1.OwnershipPercent Ownership, address TokenOwner, address TokenBorrower, address Collection, uint256 TokenId, uint256 Duration, uint256 InitialVal, address TokenOrigin) public OnlyManager {
        require(ERC721(Collection).ownerOf(TokenId) == address(this), "Token not in loan");

        TokenCollection = Collection;
        TokenID = TokenId;
        Owner = TokenOwner;
        Borrower = TokenBorrower;
        OwnershipType = Ownership;
        LoanEndTime = block.timestamp + Duration;
        InitialValue = InitialVal;
        Origin = TokenOrigin;

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

    //renew loan function, only manager, extend loan end time by duration input
    function RenewLoan(uint256 Duration) public OnlyManager {
        require(msg.sender == Manager, "Only Loans Or Treasury Contract can interact with this contract");
        require(Active == true, "Loan not active");
        LoanEndTime += Duration;
    }

    function EndLoan() public OnlyManager {
        require(msg.sender == Manager, "Only Loans Or Treasury Contract can interact with this contract");
        ERC721(TokenCollection).transferFrom(address(this), Origin, TokenID);
        
        TokenCollection = address(0);
        InitialValue = 0;
        LoanEndTime = 0;
        TokenID = 0;
        Owner = address(0);
        Borrower = address(0);
        OwnershipType = PlotsCoreV1.OwnershipPercent.Zero;
        BorrowerRewardShare = 0;
        UseCounter++;
        Active = false;
    }

    function DisperseRewards(address RewardToken) public {
        require(msg.sender == Owner || msg.sender == Borrower || msg.sender == Manager, "Only Owner or Borrower can disperse rewards");
        uint256 RewardBalance = ERC20(RewardToken).balanceOf(address(this));
        require(RewardBalance > 0, "No rewards to disperse");
        //check core contract for fee percentage and fee receiver, calculate fee and send to fee receiver
        uint256 Fee = (RewardBalance * PlotsCoreV1(Manager).RewardFee()) / 10000;
        ERC20(RewardToken).transfer(PlotsCoreV1(Manager).FeeReceiver(), Fee);
        RewardBalance -= Fee;

        uint256 OwnerReward = (RewardBalance * (10000 - BorrowerRewardShare)) / 10000;

        PlotsCoreV1(Manager).UpdateOwnerPayoutTracker(Owner, RewardToken, OwnerReward);
        PlotsCoreV1(Manager).UpdateBorrowerPayoutTracker(Borrower, RewardToken, RewardBalance - OwnerReward);
        
        ERC20(RewardToken).transfer(Owner, OwnerReward);
        ERC20(RewardToken).transfer(Borrower, ERC20(RewardToken).balanceOf(address(this)));
    }

    //create a view function that will return the unclaimed reward tokens for a user with the output depending on if the user is the owner or borrower, in a similar fashion to dispense rewards
    function GetUnclaimedRewards(address RewardToken, address User) public view returns(uint256){
        uint256 RewardBalance = ERC20(RewardToken).balanceOf(address(this));
        if(RewardBalance == 0){
            return 0;
        }
        uint256 Fee = (RewardBalance * PlotsCoreV1(Manager).RewardFee()) / 10000;
        RewardBalance -= Fee;

        uint256 OwnerReward = (RewardBalance * (10000 - BorrowerRewardShare)) / 10000;

        if(User == Owner){
            return OwnerReward;
        }
        else if(User == Borrower){
            return RewardBalance - OwnerReward;
        }
        else{
            return 0;
        }
    }

    //update borrower reward share (only manager)
    function UpdateBorrowerRewardShare(PlotsCoreV1.OwnershipPercent Ownership) public OnlyManager {
        require(Ownership != OwnershipType, "Ownership already set to this");

        BorrowerRewardShare = 0;

        OwnershipType = Ownership;

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