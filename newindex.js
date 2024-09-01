const express = require('express');
const Web3 = require('web3');
require('dotenv').config();
const bodyParser = require('body-parser');
const https = require('https');
const cors = require('cors');
const { createProxyMiddleware } = require('http-proxy-middleware');
const startTraitUpdaterServer = require('./updater');
const { getMerkleRoots, getClaimableInfo, getRemixFormat } = require('./merklegen');
const Database = require('@replit/database'); // Import as a function, not as a constructor

const app = express();
const port = process.env.PORT || 3000;
const db = new Database(); // Initialize without 'new'

// Enable trust proxy
app.set('trust proxy', 1);

const web3 = new Web3(new Web3.providers.WebsocketProvider(process.env.RPC_API_URL, {
  reconnect: {
    auto: true,
    delay: 5000, // ms
    maxAttempts: 5,
    onTimeout: false
  }
}));

const account = web3.eth.accounts.privateKeyToAccount(process.env.PRIVATE_KEY);
web3.eth.accounts.wallet.add(account);
web3.eth.defaultAccount = account.address;

const erc20Abi = [
  {
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "name": "from",
        "type": "address"
      },
      {
        "indexed": true,
        "name": "to",
        "type": "address"
      },
      {
        "indexed": false,
        "name": "value",
        "type": "uint256"
      }
    ],
    "name": "Transfer",
    "type": "event"
  }
];

const tokenAddress = '0xE382D7a7B629667476AE12e4cd4a9C3AdfC06EB5';
const tokenContract = new web3.eth.Contract(erc20Abi, tokenAddress);
const plotsCoreAddress = '0x8F0559a79E23Ef131A91F4BFD06622eA6E019ebB'; // Replace with actual PlotsCore contract address
const plotsCoreABI = [ /* ABI from the PlotsCore contract */ ];
const plotsCoreContract = new web3.eth.Contract(plotsCoreABI, plotsCoreAddress);

app.use(cors());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());

// Mappings to track amounts due and amounts paid
const amountDue = {
  '0xc932b3a342658A2d3dF79E4661f29DfF6D7e93Ce': 150  // Example amount due for this address
};

const amountPaid = {};  // This will track how much each address has paid so far

// Verbose function to get invoice details
app.get('/Invoice/:address', (req, res) => {
  const address = req.params.address;
  console.log(`Request received to check invoice for address: ${address}`);

  const due = amountDue[address];
  console.log(`Amount due for address ${address}: ${due}`);

  const paid = amountPaid[address] || 0;
  console.log(`Amount already paid by address ${address}: ${paid}`);

  // Validate the Ethereum address
  if (!web3.utils.isAddress(address)) {
    console.error(`Invalid Ethereum address: ${address}`);
    res.status(400).send('Invalid Ethereum address.');
    return;
  }

  // Check if amount due is specified and valid
  if (due === undefined) {
    console.error(`No amount due found for address: ${address}`);
    res.status(400).send('No amount due specified.');
    return;
  }

  if (due <= 0) {
    console.error(`Invalid amount due (${due}) for address: ${address}`);
    res.status(400).send('Invalid amount due specified.');
    return;
  }

  const totalPaid = paid;  // In this case, totalPaid is just the recorded amount in amountPaid
  console.log(`Total amount paid by address ${address}: ${totalPaid}`);

  // Determine if the invoice is fully paid
  const isPaid = totalPaid >= due;
  console.log(`Is the amount due fully paid? ${isPaid}`);

  // Calculate the remaining amount left to pay
  const amountLeftToPay = isPaid ? 0 : due - totalPaid;
  console.log(`Amount left to pay for address ${address}: ${amountLeftToPay}`);

  // Send back the response with the payment status and remaining amount to pay
  res.json({ Paid: isPaid, Amount: amountLeftToPay });

  console.log(`Response sent: Paid - ${isPaid}, Amount Left - ${amountLeftToPay}`);
});

// Example of how to handle payments (you may already have this elsewhere in your code)
tokenContract.events.Transfer({
  fromBlock: 'latest'
}, async (error, event) => {
  if (error) {
    console.error('Error on event', error);
  } else {
    const { from, to, value } = event.returnValues;
    const amountReceived = parseFloat(web3.utils.fromWei(value, 'ether'));
    console.log(`Transfer event detected: From ${from} to ${to}, Amount: ${amountReceived} PIXELS`);

    if (to === web3.eth.defaultAccount) {
      console.log(`Transaction received from ${from}: ${amountReceived} PIXELS`);

      // Update the amountPaid mapping with the new payment
      amountPaid[from] = (amountPaid[from] || 0) + amountReceived;

      console.log(`Total paid for ${from}: ${amountPaid[from]} PIXELS`);

      // Calculate the 70% and 30% splits
      const seventyPercent = (amountReceived * 0.7).toFixed(6);
      const thirtyPercent = (amountReceived * 0.3).toFixed(6);

      // Set a more reasonable gas price and gas limit
      const gasPrice = await web3.eth.getGasPrice();  // Get the current gas price from the network
      const gasLimit = 21000; // This is sufficient for a basic ETH transfer

      try {
        // Send 70% to a placeholder original owner
        const receipt1 = await web3.eth.sendTransaction({
          from: web3.eth.defaultAccount,
          to: '0x5B51080D8feFEC2B5f11e7275944D9816411feBe', // Placeholder for testing
          value: web3.utils.toWei(seventyPercent, 'ether'),
          gas: gasLimit,
          gasPrice: gasPrice
        });
        console.log(`Sent 70% (${seventyPercent} PIXELS) to original owner. Transaction hash: ${receipt1.transactionHash}`);

        // Update earnings history for the original owner
        const ownerHistory = (await db.get('0x5B51080D8feFEC2B5f11e7275944D9816411feBe')) || [];
        ownerHistory.push({
          payout: seventyPercent,
          unixTime: Math.floor(Date.now() / 1000)
        });
        await db.set('0x5B51080D8feFEC2B5f11e7275944D9816411feBe', ownerHistory);

        // Send 30% to the address specified
        const receipt2 = await web3.eth.sendTransaction({
          from: web3.eth.defaultAccount,
          to: '0xc932b3a342658A2d3dF79E4661f29DfF6D7e93Ce',
          value: web3.utils.toWei(thirtyPercent, 'ether'),
          gas: gasLimit,
          gasPrice: gasPrice
        });
        console.log(`Sent 30% (${thirtyPercent} PIXELS) to 0xc932b3a342658A2d3dF79E4661f29DfF6D7e93Ce. Transaction hash: ${receipt2.transactionHash}`);

        // Update earnings history for the specified address
        const addressHistory = (await db.get('0xc932b3a342658A2d3dF79E4661f29DfF6D7e93Ce')) || [];
        addressHistory.push({
          payout: thirtyPercent,
          unixTime: Math.floor(Date.now() / 1000)
        });
        await db.set('0xc932b3a342658A2d3dF79E4661f29DfF6D7e93Ce', addressHistory);

      } catch (sendError) {
        console.error('Error sending transactions:', sendError);
      }
    }
  }
});

// Endpoint to access the rewards history for a specific user
app.get('/rewards-history/:address', async (req, res) => {
  const address = req.params.address;

  if (!web3.utils.isAddress(address)) {
    res.status(400).send('Invalid Ethereum address.');
    return;
  }

  try {
    const history = await db.get(address);
    if (!history) {
      res.status(404).send('No rewards history found for this address.');
    } else {
      res.json({ address: address, rewardsHistory: history });
    }
  } catch (error) {
    console.error('Error fetching rewards history:', error);
    res.status(500).send('Error fetching rewards history');
  }
});

// Schedule route
app.get('/schedule', (req, res) => {
  const roots = getMerkleRoots();
  res.json({ schedule: roots });
});

// Remix deployment route
app.get('/merkle/deploy', (req, res) => {
  const remixFormat = getRemixFormat();
  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Remix Deployment Parameters</title>
    </head>
    <body>
      <h1>Remix Deployment Parameters</h1>
      ${remixFormat}
    </body>
    </html>
  `);
});

// New endpoint to get claimable info for a given address
app.get('/schedule/:address', async (req, res) => {
  const address = req.params.address;

  if (!web3.utils.isAddress(address)) {
    res.status(400).send('Invalid Ethereum address.');
    return;
  }

  try {
    const claimableInfo = await getClaimableInfo(address);
    res.json({ address: address, claimableDistributions: claimableInfo });
  } catch (error) {
    if (error.message === 'No distributor contract found.') {
      res.status(500).send('No distributor contract found.');
    } else {
      console.error('Error fetching claimable info:', error);
      res.status(500).send('Error fetching claimable info');
    }
  }
});

// Proxy middleware for trait updater server under /serviceb prefix
app.use('/traits', createProxyMiddleware({
  target: 'http://localhost:3001',
  changeOrigin: true,
  pathRewrite: {
    '^/traits': ''
  }
}));

// Start the servers
app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});

// Start the trait updater server on a different port
startTraitUpdaterServer(3001);
