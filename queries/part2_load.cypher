// ==========================================
// ЗАВАНТАЖЕННЯ
// ==========================================

// БЛОК 1: Створення обмежень унікальності та індексів
CREATE CONSTRAINT user_id_unique IF NOT EXISTS FOR (u:User) REQUIRE u.userId IS UNIQUE;
CREATE CONSTRAINT movie_id_unique IF NOT EXISTS FOR (m:Movie) REQUIRE m.movieId IS UNIQUE;
CREATE INDEX genre_name_index IF NOT EXISTS FOR (g:Genre) ON (g.name);

// БЛОК 2: Завантаження користувачів
LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
MERGE (u:User {userId: toInteger(row.userId)})
SET u.gender = row.gender,
    u.age = toInteger(row.age),
    u.occupation = toInteger(row.occupation);

// БЛОК 3: Завантаження фільмів та створення унікальних жанрів
LOAD CSV WITH HEADERS FROM 'file:///movies.csv' AS row
MERGE (m:Movie {movieId: toInteger(row.movieId)})
WITH m, row
WITH m, row, apoc.text.regexGroups(row.title, "(.*) \\((\\d{4})\\)") AS match
SET m.title = CASE WHEN size(match) > 0 THEN trim(match[0][1]) ELSE row.title END,
    m.year = CASE WHEN size(match) > 0 THEN toInteger(match[0][2]) ELSE null END
WITH m, row
UNWIND split(row.genres, '|') AS genreName
MERGE (g:Genre {name: genreName})
MERGE (m)-[:HAS_GENRE]->(g);

// БЛОК 4: Пакетне завантаження ребер оцінок (через APOC)
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM 'file:///ratings.csv' AS row RETURN row",
  "MATCH (u:User {userId: toInteger(row.userId)})
   MATCH (m:Movie {movieId: toInteger(row.movieId)})
   MERGE (u)-[r:RATED]->(m)
   SET r.rating = toInteger(row.rating),
       r.timestamp = toInteger(row.timestamp)",
  {batchSize: 20000, parallel: false}
);

// Перевірка
MATCH (u:User) RETURN count(u) AS users;
MATCH (m:Movie) RETURN count(m) AS movies;
MATCH ()-[r:RATED]->() RETURN count(r) AS ratings;