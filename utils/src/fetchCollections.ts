import { writeFile } from 'fs/promises';
import { join } from 'path';
const { OPENSEA_API_KEY } = process.env;

if (!OPENSEA_API_KEY) throw new Error('OPENSEA KEY missing');

const url = new URL('https://api.opensea.io/api/v2/collections');

url.searchParams.set('chain', 'base');
url.searchParams.set('include_hidden', 'false');
url.searchParams.set('limit', '100');
url.searchParams.set('order_by', 'num_owners');

const options = {
    method: 'GET',
    headers: {
        Accept: 'application/json',
        'x-api-key': OPENSEA_API_KEY,
    },
};

type CollectionItem = {
    name: string;
    collection: string;
    contracts: [{ address: string }];
};

type ApiResponse = {
    collections: CollectionItem[];
    next: string;
};

async function fetchCollections() {
    let cursor = '';
    const filePath = join(__dirname, 'collections.json');

    const collectionData: { items: CollectionItem[] } = { items: [] };

    for (let i = 0; i < 50; i++) {
        url.searchParams.set('next', cursor);

        const res = await fetch(url, options);
        if (!res.ok) {
            throw new Error(`HTTP error! status: ${res.status}`);
        }
        const data = (await res.json()) as ApiResponse;

        if (!data.collections) {
            console.log('could not get collections');
            return;
        }

        const tokens = data.collections;

        for (const token of tokens) {
            collectionData.items.push({
                name: token.name,
                collection: token.collection,
                contractAddr: token.contracts[0]?.address,
            });
        }

        console.log('Number of collections found:', data.collections.length);
        console.log('First collection name:', data.collections[0].name);
        cursor = data.next;

        console.log(data.next);
    }

    await writeFile(filePath, JSON.stringify(collectionData));
}

fetchCollections().catch((err) => console.log(err));
