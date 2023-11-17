// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

contract PlotsCore{
    //Variable and pointer Declarations
    address public Treasury;
    address public LendContract;
    address[] public ListedCollections;

    enum ListingType{
        Ownership,
        Usage
    }

    enum OwnershipPercent{
        Ten,
        TwentyFive
    }
    
    struct Listing{
        address Collection;
        uint256 TokenId;
        uint256 Value;
        ListingType OwnershipOption;
    }

    struct LoanedToken{
        address Borrower;
        address Collection;
        uint256 TokenId;
        uint256 Value;
        uint256 LoanLength;
        uint256 LoanStartTime;
        bool Active;
    }

    mapping(address => bool) public Admins;
    modifier OnlyAdmin(){
        require(Admins[msg.sender], "Only Admin");
        _;
    }

    mapping(address => uint256[]) public AvailableTokensByCollection;
    mapping(address => mapping(uint256 => uint256)) public AvailableTokensByCollectionIndex;

    //make a mapping like the last one to store all loans by collection
    mapping(address => LoanedToken[]) public LoansByCollection;
    mapping(address => mapping(uint256 => uint256)) public LoansByCollectionIndex;

    mapping(address => uint256) public ListedCollectionsIndex;
    mapping(address => mapping(address => uint256)) public OwnershipByPurchase;

    mapping(address => LoanedToken[]) public AllUserLoans;
    mapping(address => mapping(uint256 => uint256)) public AllUserLoansIndex;

    mapping(address => mapping(uint256 => Listing)) public Listings;
    

    constructor(address [] memory _admins){
        Treasury = address(0);
        for(uint256 i = 0; i < _admins.length; i++){
            Admins[_admins[i]] = true;
        }
    }

    //Super admin

    //Public Functions

    function RequestToken(address Collection, uint256 TokenId) public payable {
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(AvailableTokensByCollectionIndex[Collection][TokenId] != 0, "Token not listed");
        require(OwnershipByPurchase[Collection][msg.sender] == 0, "Already requested token");
        
        if(Listings[Collection][TokenId].OwnershipOption == ListingType.Ownership){
            require(msg.value == Listings[Collection][TokenId].Value, "Incorrect tx value");
        }
        else{
            require(msg.value == 0, "Do not Pay for usage tokens");
        }

        OwnershipByPurchase[Collection][msg.sender] = TokenId;
    }

    function ListTokenForUsage(address Collection, uint256 TokenId) public{
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(AvailableTokensByCollectionIndex[Collection][TokenId] == 0, "Token already listed");
        //setup listing

        Listings[Collection][TokenId] = Listing(Collection, TokenId, 0, ListingType.Usage);

        AvailableTokensByCollection[Collection].push(TokenId);
        AvailableTokensByCollectionIndex[Collection][TokenId] = AvailableTokensByCollection[Collection].length - 1;
    }


    //Public View Functions

    function GetAvailableTokensByCollection(address _collection) public view returns(uint256[] memory){
        return AvailableTokensByCollection[_collection];
    }

    function GetListedCollections() public view returns(address[] memory){
        return ListedCollections;
    }
    
    //new view functions
    //Function to allow frontend see all user owned
    //Listings by user

    function GetSingularListing(address _collection, uint256 _tokenId) public view returns(Listing memory){
        return Listings[_collection][_tokenId];
    }

    function GetListedCollection(address _collection) public view returns(Listing[] memory){
        Listing[] memory _listings = new Listing[](AvailableTokensByCollection[_collection].length);
        for(uint256 i = 0; i < AvailableTokensByCollection[_collection].length; i++){
            _listings[i] = Listings[_collection][AvailableTokensByCollection[_collection][i]];
        }
        return _listings;
    }

    //Only Admin Functions

    function ListTokenForOwnership(address Collection, uint256 TokenId, uint256 Value) public OnlyAdmin{
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(AvailableTokensByCollectionIndex[Collection][TokenId] == 0, "Token already listed");
        //require(ERC721(Collection).ownerOf(TokenId) == Treasury, "Token not owned by treasury");

        Listings[Collection][TokenId] = Listing(Collection, TokenId, Value, ListingType.Ownership);

        AvailableTokensByCollection[Collection].push(TokenId);
        AvailableTokensByCollectionIndex[Collection][TokenId] = AvailableTokensByCollection[Collection].length - 1;
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

