const { Client } = require('pg');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

const dbConfig = {
    user: process.env.DB_USER || 'postgres',
    host: process.env.DB_HOST || 'localhost',
    password: process.env.DB_PASSWORD || 'postgres',
    port: parseInt(process.env.DB_PORT || '5432', 10),
};

const targetDb = process.env.DB_NAME || 'edudb';

async function initDatabase() {
    console.log('🔄 Step 1: Checking and creating database if not exists...');
    
    // Connect to default 'postgres' database
    const adminClient = new Client({
        ...dbConfig,
        database: 'postgres',
    });

    try {
        await adminClient.connect();
        const checkDb = await adminClient.query(
            "SELECT 1 FROM pg_database WHERE datname = $1",
            [targetDb]
        );

        if (checkDb.rowCount === 0) {
            console.log(`Creating database "${targetDb}"...`);
            await adminClient.query(`CREATE DATABASE "${targetDb}"`);
            console.log(`Database "${targetDb}" created successfully.`);
        } else {
            console.log(`Database "${targetDb}" already exists.`);
        }
    } catch (err) {
        console.error('Error connecting to postgres default db:', err.code, err.message, err);
        throw err;
    } finally {
        await adminClient.end();
    }

    console.log(`🔄 Step 2: Connecting to "${targetDb}" to run Schema and Seed...`);
    const appClient = new Client({
        ...dbConfig,
        database: targetDb,
    });

    try {
        await appClient.connect();

        // 1. Run schema.sql
        const schemaPath = path.join(__dirname, 'schema.sql');
        const schemaSql = fs.readFileSync(schemaPath, 'utf8');
        console.log('Executing schema.sql (Tables, Triggers, Stored Procedures)...');
        await appClient.query(schemaSql);
        console.log('✅ Schema created successfully!');

        // 2. Run seed.sql
        const seedPath = path.join(__dirname, 'seed.sql');
        const seedSql = fs.readFileSync(seedPath, 'utf8');
        console.log('Executing seed.sql (Initial records & demo data)...');
        await appClient.query(seedSql);
        console.log('✅ Seed data inserted successfully!');

        console.log('\n======================================================');
        console.log('🎉 Database initialization complete!');
        console.log(`Tables, Triggers, and Stored Procedures are ready in "${targetDb}".`);
        console.log('======================================================\n');
    } catch (err) {
        console.error('Error executing SQL files:', err.message);
        throw err;
    } finally {
        await appClient.end();
    }
}

if (require.main === module) {
    initDatabase().catch((err) => {
        console.error('❌ Database initialization failed:', err.message);
        process.exit(1);
    });
}

module.exports = initDatabase;
