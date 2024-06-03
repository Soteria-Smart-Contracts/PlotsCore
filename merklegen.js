console.log('merklegen.js loaded');
loginWithEth()

async function loginWithEth(){
      if(window.ethereum){
          await ethereum.request({ method: 'eth_requestAccounts' });
          window.web3 = await new Web3(ethereum);
          accountarray = await web3.eth.getAccounts();
          account = accountarray[0];
          console.log('Logged In')
          GenerateStuff();

          return(true)
      } 
      else { 
          alert("No ETHER Wallet available")
      }
}

let WhitelistMerkleTree;
let leafNodesWhitelist;
let rootHashWhitelist;

function GenerateStuff(){
    //convert the whitelistAddresses to an array of addresses with the points number appended to the address end
    let WhitelistAddresses = data2.map(address => web3.utils.encodePacked({value: address.address, type: 'address'}));

    let ClaimantAddresses = data1.map(address => web3.utils.encodePacked({value: address.address + address.points, type: 'string'}));

    WhitelistAddresses = WhitelistAddresses.concat(ClaimantAddresses);

    console.log(WhitelistAddresses);

    leafNodesWhitelist = WhitelistAddresses.map(addr => keccak256(addr));
    WhitelistMerkleTree = new MerkleTree(leafNodesWhitelist, keccak256, { sortPairs: true });

    // Get the Merkle Root of the Merkle Tree
    rootHashWhitelist = WhitelistMerkleTree.getRoot();
    let rootHashWhitelistBytes32 = '0x' + WhitelistMerkleTree.getRoot().toString('hex');
    console.log("Root Hash Whitelist: ", rootHashWhitelistBytes32);
}

// Function to generate hex proof for a claiming address
function GenerateHexProofWhitelist(claimingAddress, points) {
  if(points > 0){
    claimingAddress = web3.utils.encodePacked({value: claimingAddress + points, type: 'string'})
  }

  claimingAddress = keccak256(web3.utils.encodePacked(claimingAddress));
  console.log(claimingAddress)
  const hexProof = WhitelistMerkleTree.getHexProof(claimingAddress);
  const isAddressInTree = WhitelistMerkleTree.verify(hexProof, claimingAddress, rootHashWhitelist);
  //get the lea

  return {
    hexProof: hexProof,
    isAddressInTree: isAddressInTree
  };
}
