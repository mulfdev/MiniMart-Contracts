import 'dotenv';
import { config } from 'dotenv';
import { join } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

config({ path: join(__dirname, '../../.env') });

import { execSync } from 'child_process';
import { privateKeyToAccount } from 'viem/accounts';

const getFoundryPrivateKey = (accountName: string) => {
    const password = process.env.KEYSTORE_PASSWORD;

    if (!password) {
        throw new Error('KEYSTORE_PASSWORD environment variable is required');
    }

    try {
        const result = execSync(
            `cast wallet private-key --keystore ~/.foundry/keystores/${accountName} --password "${password}"`,
            { encoding: 'utf8' }
        );
        return result.trim();
    } catch (error) {
        console.log(error);
        throw new Error('Failed to retrieve private key from Foundry keystore');
    }
};
const privateKey = getFoundryPrivateKey('mulf-deployer');
export const account = privateKeyToAccount(privateKey as `0x${string}`);
console.log(account.address);
