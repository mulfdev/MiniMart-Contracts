import { writeFile } from 'fs/promises';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
const { OPENSEA_API_KEY } = process.env;

if (!OPENSEA_API_KEY) throw new Error('OPENSEA KEY missing');

const url = new URL('https://api.opensea.io/api/v2/collections');

url.searchParams.set('chain', 'base');
url.searchParams.set('include_hidden', 'false');
url.searchParams.set('limit', '100');
url.searchParams.set('order_by', 'market_cap');

const options = {
    method: 'GET',
    headers: {
        Accept: 'application/json',
        'x-api-key': OPENSEA_API_KEY,
    },
};

interface CollectionItem {
    name: string;
    collection: string;
    contracts: [{ address: string }];
}

interface ApiResponse {
    collections?: CollectionItem[];
    next?: string;
}

async function fetchCollections() {
    let cursor = '';
    const __dirname = dirname(fileURLToPath(import.meta.url));

    const filePath = join(__dirname, 'collections.json');

    const collectionData: { items: { name: string; collection: string; contractAddr: string }[] } =
        { items: [] };

    for (let i = 0; i < 50; i++) {
        url.searchParams.set('next', cursor);

        const res = await fetch(url, options);
        if (!res.ok) {
            throw new Error(`HTTP error! status: ${res.status}`);
        }
        const data = (await res.json()) as ApiResponse;

        const tokens = data.collections ?? [];

        if (!tokens) {
            throw new Error('Couldnt fetch collections');
        }

        for (const token of tokens) {
            collectionData.items.push({
                name: token.name,
                collection: token.collection,
                contractAddr: token.contracts[0]?.address,
            });
        }

        console.log('Number of collections found:', data?.collections?.length);
        console.log('First collection name:', data?.collections?.[0]?.name);

        if (!data.next) return;
        cursor = data.next;

        console.log(data.next);
    }

    await writeFile(filePath, JSON.stringify(collectionData));
}

fetchCollections().catch((err) => console.log(err));
