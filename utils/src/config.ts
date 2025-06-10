import { http, createConfig } from '@wagmi/core';
import { base, baseSepolia } from '@wagmi/core/chains';
import { execSync } from 'child_process';
import { privateKeyToAccount } from 'viem/accounts';

const getFoundryPrivateKey = (accountName: string, password: string) => {
    try {
        const result = execSync(`echo "${password}" | cast wallet private-key ${accountName}`, {
            encoding: 'utf8',
            stdio: ['pipe', 'pipe', 'pipe'],
        });
        return result.trim() as `0x${string}`;
    } catch (error) {
        console.log(error);
        throw new Error('Failed to retrieve private key from Foundry keystore');
    }
};

const privateKey = getFoundryPrivateKey('your-account-name', process.env.FOUNDRY_PASSWORD!);
export const account = privateKeyToAccount(privateKey);

export const config = createConfig({
    chains: [base, baseSepolia],
    transports: {
        [base.id]: http(),
        [baseSepolia.id]: http(),
    },
});
