// =========================================================================
// ГРАФОВІ АЛГОРИТМИ ЧЕРЕЗ GDS
// =========================================================================

// 5.1. PageRank на графі фільмів

// Крок 1: Матеріалізуємо ребра фільм-фільм через спільних користувачів
// ПРИМІТКА: Для оптимізації та уникнення таймауту на повних даних підвищено рейтинг до = 5
MATCH (m1:Movie)<-[r1:RATED]-(u:User)-[r2:RATED]->(m2:Movie)
WHERE r1.rating = 5 AND r2.rating = 5 AND id(m1) < id(m2)
WITH m1, m2, count(u) AS weight
WHERE size([(m1)<-[:RATED]-() | 1]) > 20
  AND size([(m2)<-[:RATED]-() | 1]) > 20
WITH m1, m2, weight
ORDER BY weight DESC
LIMIT 30000 // Зменшено ліміт для швидшої матеріалізації на локальній машині
MERGE (m1)-[co:CO_RATED]-(m2)
SET co.weight = weight;

// Крок 2: Створюємо проєкцію графа в пам'яті GDS на основі створених ребер CO_RATED
CALL gds.graph.project(
  'movieGraph',
  'Movie',
  { CO_RATED: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: Запуск алгоритму PageRank (Стрімінговий режим)
CALL gds.pageRank.stream('movieGraph', {
  maxIterations: 20,
  dampingFactor: 0.85,
  relationshipWeightProperty: 'weight'
})
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).title AS MovieTitle, 
       gds.util.asNode(nodeId).year AS ReleaseYear, 
       round(score, 4) AS PageRankScore
ORDER BY PageRankScore DESC
LIMIT 10;

// Крок 4: Очищення - видаляємо проєкцію з пам'яті та тимчасові ребра з бази
CALL gds.graph.drop('movieGraph');
MATCH ()-[co:CO_RATED]-() DELETE co;

// 5.2. Виявлення спільнот (Louvain) серед користувачів

// Крок 1: Матеріалізація ребер користувач-користувач
CALL apoc.periodic.iterate(
  "MATCH (u1:User) WHERE COUNT { (u1)-[:RATED]->() } > 20
   MATCH (u2:User) WHERE COUNT { (u2)-[:RATED]->() } > 20 AND id(u1) < id(u2)
   MATCH (u1)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2)
   WHERE r1.rating >= 4 AND r2.rating >= 4
   WITH u1, u2, count(m) AS weight
   WHERE weight >= 5
   RETURN u1, u2, weight",
  "MERGE (u1)-[sim:SIMILAR]-(u2)
   SET sim.weight = weight",
  {batchSize: 5000, parallel: false}
);

// Крок 2: Створення проєкції в пам'яті GDS
CALL gds.graph.project(
  'userSimilarity',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: Запуск Louvain у режимі WRITE (записуємо ID спільноти у вузли для подальшого аналізу)
CALL gds.louvain.write('userSimilarity', {
  writeProperty: 'communityId',
  relationshipWeightProperty: 'weight'
})
YIELD communityCount, modularity, modularities;

// Крок 4а: Вивід 10 найбільших кластерів за розміром
MATCH (u:User)
WHERE u.communityId IS NOT NULL
RETURN u.communityId AS CommunityID, count(u) AS ClusterSize
ORDER BY ClusterSize DESC
LIMIT 10;

// Крок 4б: Визначення ТОП-3 найпопулярніших жанрів для найбільших спільнот
MATCH (u:User)-[r:RATED]->(m:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE u.communityId IS NOT NULL AND r.rating >= 4
WITH u.communityId AS CommunityID, g.name AS GenreName, count(r) AS GenreCount
ORDER BY CommunityID, GenreCount DESC
WITH CommunityID, collect({genre: GenreName, count: GenreCount})[..3] AS TopGenres
RETURN CommunityID, TopGenres
ORDER BY size(TopGenres) DESC
LIMIT 10;

// Додатковий крок 1 - хронологічна 4887 та 4646
MATCH (u:User)-[r:RATED]->(m:Movie)
WHERE u.communityId IN [4887, 4646] AND r.rating >= 4
RETURN u.communityId AS CommunityID,
       avg(m.year) AS AverageYear,
       min(m.year) AS OldestMovie,
       max(m.year) AS NewestMovie
ORDER BY AverageYear DESC;

// Додатковий крок 2 - топ-10 фільмів кластерів 4887 та 4646
MATCH (u:User)-[r:RATED]->(m:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE u.communityId IN [4887, 4646] AND r.rating >= 4 AND g.name IN ['Drama', 'Comedy', 'Thriller']
WITH u.communityId AS CommunityID, g.name AS GenreName, m.title AS MovieTitle, count(r) AS Votes
ORDER BY CommunityID, GenreName, Votes DESC
WITH CommunityID, GenreName, collect({movie: MovieTitle, votes: Votes})[..10] AS TopMoviesPerGenre
ORDER BY CommunityID, GenreName
RETURN CommunityID, GenreName, TopMoviesPerGenre;

// Додатковий крок 3 - аналіз за віком кластерів 4887 та 4646
MATCH (u:User)
WHERE u.communityId IN [4887, 4646]
RETURN u.communityId AS CommunityID,
       avg(u.age) AS AverageAge,
       min(u.age) AS YoungestUser,
       max(u.age) AS OldestUser,
       count(u) AS TotalUsersInQuery
ORDER BY AverageAge DESC;

// Крок 5: Очищення — видалення проєкції та тимчасових ребер
Команда 1:
CALL gds.graph.drop('userSimilarity');

Команда 2:
:auto
MATCH ()-[sim:SIMILAR]->()
CALL {
    WITH sim
    DELETE sim
} IN TRANSACTIONS OF 100000 ROWS;

// 5.3. Виявлення спільнот (Louvain) серед користувачів

// Крок 1: Будуємо "легкий" граф (лише 50 000 найсильніших зв'язків)
CALL apoc.periodic.iterate(
  "MATCH (u1:User) RETURN u1",
  "MATCH (u1)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
   WHERE r1.rating >= 4 AND r2.rating >= 4 AND id(u1) < id(u2)
   WITH u1, u2, count(m) AS weight
   WHERE weight >= 10
   WITH u1, u2, weight ORDER BY weight DESC LIMIT 20
   MERGE (u1)-[sim:SIMILAR]-(u2)
   SET sim.weight = weight",
  {batchSize: 50, parallel: false}
);

// Крок 2. Проєктуємо новий граф у пам'ять GDS
CALL gds.graph.project(
  'userGraph',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: Запит для розрахунку середньої довжини шляху
MATCH (u1:User), (u2:User)
WHERE id(u1) <> id(u2)
WITH u1, u2, rand() AS r
ORDER BY r LIMIT 100

CALL gds.shortestPath.dijkstra.stream('userGraph', {
    sourceNode: u1,
    targetNode: u2
})
YIELD totalCost
WHERE totalCost > 0 // Відкидаємо нульові результати
RETURN avg(totalCost) AS AveragePathLength, 
       max(totalCost) AS MaximumHandshakes,
       min(totalCost) AS MinimumHandshakes,
       count(*) AS SuccessfulPaths;

// Крок 4. Запит для розрахунку найдовшого шляху
MATCH (u1:User)-[:SIMILAR]-()
WITH DISTINCT u1
MATCH (u2:User)-[:SIMILAR]-()
WHERE id(u1) < id(u2) // Беремо унікальні пари і виключаємо порівняння із собою
WITH u1, u2, rand() AS r
ORDER BY r LIMIT 10000

CALL gds.shortestPath.dijkstra.stream('userGraph', {
    sourceNode: u1,
    targetNode: u2
})
YIELD totalCost
WHERE totalCost > 0 // Відкидаємо тих, хто на різних "островах"
RETURN max(totalCost) AS AbsoluteMaximumPath,
       avg(totalCost) AS AveragePathLength,
       count(*) AS SuccessfulPaths;

// Крок 5. Запускаємо алгоритм Дейкстри
MATCH (source:User)-[:SIMILAR]-(), (target:User)-[:SIMILAR]-()
WHERE id(source) < id(target)
WITH source, target, rand() AS r
ORDER BY r LIMIT 1

CALL gds.shortestPath.dijkstra.stream('userGraph', {
    sourceNode: source,
    targetNode: target
})
YIELD totalCost, nodeIds
WHERE totalCost > 0
RETURN id(source) AS UserA, 
       id(target) AS UserB, 
       totalCost AS NumberOfHandshakes,
       nodeIds AS PathOfUsers;

// Крок 5. Графове зобрраження (додатково)
MATCH path = (u1:User)-[:SIMILAR]-(u2:User)-[:SIMILAR]-(u3:User)
WHERE id(u1) = 450 AND id(u2) = 4168 AND id(u3) = 4276
RETURN path; 

// Крок 6. Аналіз перепиту кіно-спільнот з кластерів запитів до 5.2
MATCH (u1:User)-[:SIMILAR]-(u2:User)-[:SIMILAR]-(u3:User)
WHERE id(u1) = 450 AND id(u2) = 4168 AND id(u3) = 4276
RETURN id(u1) AS User450, u1.communityId AS Community450,
       id(u2) AS User4168_Bridge, u2.communityId AS BridgeCommunity,
       id(u3) AS User4276, u3.communityId AS Community4276;

// Крок 7. Очищення - видаляємо проєкцію з пам'яті та тимчасові ребра з бази
CALL gds.graph.drop('userGraph', false);
MATCH (u:User) REMOVE u.communityId;
MATCH ()-[sim:SIMILAR]-() DELETE sim;