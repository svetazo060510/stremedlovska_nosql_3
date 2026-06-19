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