import Foundation

/// Ordered schema migrations, tracked with `PRAGMA user_version`.
enum Schema {
    static let migrations: [String] = [
        """
        CREATE TABLE projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            is_inbox INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            parent_id INTEGER REFERENCES tasks(id) ON DELETE CASCADE,
            content TEXT NOT NULL,
            details TEXT NOT NULL DEFAULT '',
            is_completed INTEGER NOT NULL DEFAULT 0,
            completed_at REAL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            is_collapsed INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );
        CREATE INDEX tasks_project ON tasks(project_id);
        CREATE INDEX tasks_parent ON tasks(parent_id);
        """
    ]

    static func migrate(_ database: SQLiteDatabase) throws {
        let current = try database.query("PRAGMA user_version") { Int($0.int(0)) }.first ?? 0
        for (index, migration) in migrations.enumerated() where index >= current {
            try database.transaction {
                try database.execute(migration)
                try database.execute("PRAGMA user_version = \(index + 1)")
            }
        }
    }
}
