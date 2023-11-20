// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

contract PlotsCore {
    //Variable and pointer Declarations
    address public Treasury;
    address public LendContract;
    address[] public ListedCollections;

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
        address Collection;
        uint256 TokenId;
        ListingType OwnershipOption;
    }

    struct LoanedToken{
        address Borrower;
        address Collection;
        uint256 TokenId;
        OwnershipPercent Ownership;
        LengthOption Duration;
        uint256 LoanLength;
        uint256 LoanStartTime;
        bool Active;
    }

    mapping(address => bool) public Admins;
    modifier OnlyAdmin(){
        require(Admins[msg.sender], "Only Admin");
        _;
    }

    //Listings for assets available for borrowing
    mapping(address => Listing[]) public ListingByCollection;
    mapping(address => mapping(uint256 => uint256)) public ListingByCollectionIndex;

    //Borrowed tokens 
    mapping(address => LoanedToken[]) public LoansByCollection;
    mapping(address => mapping(uint256 => uint256)) public LoansByCollectionIndex;

    mapping(address => LoanedToken[]) public AllUserLoans;
    mapping(address => mapping(uint256 => uint256)) public AllUserLoansIndex;

    mapping(address => mapping(address => uint256)) public OwnershipByPurchase;
    mapping(address => uint256) public ListedCollectionsIndex;


    constructor(address [] memory _admins){
        Treasury = address(new PlotsTreasury(address(this)));
        Treasury = address(0);
        for(uint256 i = 0; i < _admins.length; i++){
            Admins[_admins[i]] = true;
        }
    }

    //Super admin

    //Public Functions

    function RequestToken(address Collection, uint256 TokenId, LengthOption Duration) public payable {
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(ListingByCollectionIndex[Collection][TokenId] != 0, "Token not listed");
        require(OwnershipByPurchase[Collection][msg.sender] == 0, "Already requested token");
        
        if(ListingByCollection[Collection][TokenId].OwnershipOption == ListingType.Ownership){
            require(msg.value == ListingByCollection[Collection][TokenId].Value, "Incorrect tx value");
        }
        else{
            require(msg.value == 0, "Do not Pay for usage tokens");
        }

        OwnershipByPurchase[Collection][msg.sender] = TokenId;
    }

    function ListTokenForUsage(address Collection, uint256 TokenId) public{
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(ListingByCollectionIndex[Collection][TokenId] == 0, "Token already listed");

        ListingByCollection[Collection][TokenId] = Listing(Collection, TokenId, 0, ListingType.Usage);

        ListingByCollection[Collection].push(TokenId);
        ListingByCollectionIndex[Collection][TokenId] = ListingByCollection[Collection].length - 1;
    }


    //Public View Functions

    function GetListingByCollection(address _collection) public view returns(uint256[] memory){
        return ListingByCollection[_collection];
    }

    function GetListedCollections() public view returns(address[] memory){
        return ListedCollections;
    }
    
    //Function to allow frontend see all user loaned tokens (that they put up collateral to borrow)
    function GetUserLoans(address _user) public view returns(LoanedToken[] memory){
        return AllUserLoans[_user];
    }

    //Listings by user
    function GetUserListings(address _user) public view returns(Listing[] memory){
        Listing[] memory _listings = new Listing[](ListingByCollection[_user].length);
        for(uint256 i = 0; i < ListingByCollection[_user].length; i++){
            _listings[i] = ListingByCollection[_user][ListingByCollection[_user][i]];
        }
        return _listings;
    }

    function GetSingularListing(address _collection, uint256 _tokenId) public view returns(Listing memory){
        return ListingByCollection[_collection][_tokenId];
    }

    function GetListedCollection(address _collection) public view returns(Listing[] memory){
        Listing[] memory _listings = new Listing[](ListingByCollection[_collection].length);
        for(uint256 i = 0; i < ListingByCollection[_collection].length; i++){
            _listings[i] = ListingByCollection[_collection][ListingByCollection[_collection][i]];
        }
        return _listings;
    }

    //Internal Functions

    function AddListingToCollection(address _collection, uint256 _tokenId) internal{
        ListingByCollection[_collection].push(_tokenId);
        ListingByCollectionIndex[_collection][_tokenId] = ListingByCollection[_collection].length - 1;
    }

    //Only Admin Functions

    function ListTokenForOwnership(address Collection, uint256 TokenId, uint256 Value) public OnlyAdmin{
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(ListingByCollectionIndex[Collection][TokenId] == 0, "Token already listed");
        require(ERC721(Collection).ownerOf(TokenId) == Treasury, "Token not owned by treasury");

        ListingByCollection[Collection][TokenId] = Listing(Collection, TokenId, Value, ListingType.Ownership);

        ListingByCollection[Collection].push(TokenId);
        ListingByCollectionIndex[Collection][TokenId] = ListingByCollection[Collection].length - 1;
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
    //Okay I am creating a new concept called floor factor, which is essentially a multiplier that is calculated when an NFT is deposited into the contract, we use the price of the NFT and the floor price to calculate the floor factor, which allows us to estimate a future price of the nft based on the floor price and the rarity of the nft, lets start by creating a mapping for each nft to each collection
    mapping(address => mapping(uint256 => uint256)) public TokenFloorFactor;

    constructor(address Core){
        PlotsCoreContract = Core;
    }

    //allow admin to deposit nft into treasury
    function DepositNFT(address Collection, uint256 TokenId, uint256 EtherCost) public {
        require(ERC721(Collection).ownerOf(TokenId) == msg.sender, "Not owner of token");
        ERC721(Collection).transferFrom(msg.sender, PlotsCoreContract, TokenId);

        //calculate floor factor
        TokenFloorFactor[Collection][TokenId] = (EtherCost / CollectionFloorPrice[Collection]);
    }

    //allow admin to withdraw nft from treasury

    function WithdrawNFT(address Collection, uint256 TokenId) public {
        require(ERC721(Collection).ownerOf(TokenId) == PlotsCoreContract, "Not owner of token");
        ERC721(Collection).transferFrom(PlotsCoreContract, msg.sender, TokenId);
    }

    //allow admin to set floor price for multiple collections at once, with an array with the collections and an array with the floor prices
    function SetFloorPrice(address[] memory Collections, uint256[] memory FloorPrices) public {
        require(Collections.length == FloorPrices.length, "Arrays not same length");
        for(uint256 i = 0; i < Collections.length; i++){
            CollectionFloorPrice[Collections[i]] = FloorPrices[i];
        }
    }

    //view functions

    function GetFloorPrice(address Collection) public view returns(uint256){
        return CollectionFloorPrice[Collection];
    }

    function GetFloorFactor(address Collection, uint256 TokenId) public view returns(uint256){
        return TokenFloorFactor[Collection][TokenId];
    }

    function GetTokenValueFloorAdjusted(address Collection, uint256 TokenId) public view returns(uint256){
        return CollectionFloorPrice[Collection] * TokenFloorFactor[Collection][TokenId];
    }

}

contract PlotsLend{
    //Variable and pointer Declarations
    address public PlotsCoreContract;

    constructor(address Core){
        PlotsCoreContract = Core;
        
    }

    //allow a user to deposit a token into the lending contract from any collection that is listed on the core contract
    function DepositToken(address Collection, uint256 TokenId) public{
        require(ERC721(Collection).ownerOf(TokenId) == msg.sender, "Not owner of token");
        ERC721(Collection).transferFrom(msg.sender, address(this), TokenId);
    }

    function WithdrawToken(address Collection, uint256 TokenId) public{
        require(ERC721(Collection).ownerOf(TokenId) == PlotsCoreContract, "Not owner of token");
        ERC721(Collection).transferFrom(address(this), msg.sender, TokenId);
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
