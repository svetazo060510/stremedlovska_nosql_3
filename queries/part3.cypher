// ==========================================
// БАЗОВІ ЗАПИТИ
// ==========================================

// Крок 1: Фільми жанру Thriller із середнім рейтингом > 4.0
MATCH (g:Genre {name: "Thriller"})<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-()
WITH m, avg(r.rating) AS avgRating
WHERE avgRating > 4.0
RETURN m.title AS Title, m.year AS Year, round(avgRating, 2) AS AverageRating
ORDER BY AverageRating DESC;

// Крок 2: Користувачі, які поставили оцінку 5 більше ніж 50 фільмам
MATCH (u:User)-[r:RATED]->(:Movie)
WHERE r.rating = 5
WITH u, count(r) AS countOfFives
WHERE countOfFives > 50
RETURN u.userId AS UserID, u.gender AS Gender, u.age AS Age, countOfFives AS TotalFives
ORDER BY TotalFives DESC;


// ==========================================
// ЗАПИТИ СЕРЕДНЬОГО РІВНЯ
// ==========================================

// Крок 3: Спільні фільми користувачів #1 та #2 з рейтингом >= 4
MATCH (u1:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User {userId: 2})
WHERE r1.rating >= 4 AND r2.rating >= 4
RETURN m.title AS Title, m.year AS Year, r1.rating AS RatingUser1, r2.rating AS RatingUser2
ORDER BY Title ASC;

// Крок 4: Жанри, чиї фільми стабільно отримують високі оцінки
MATCH (g:Genre)<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-()
WITH g, avg(r.rating) AS avgRating, count(r) AS totalRatings
WHERE avgRating > 3.6 AND totalRatings > 10000
RETURN g.name AS Genre, round(avgRating, 3) AS AverageRating, totalRatings AS TotalRatings
ORDER BY AverageRating DESC;


// ==========================================
// СКЛАДНІ ЗАПИТИ
// ==========================================

// Крок 5 (Варіант А): Класична фільтрація (Базовий)
MATCH (u:User {userId: 1})-[r1:RATED]->(m1:Movie)<-[r2:RATED]-(peer:User)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND u <> peer
MATCH (peer)-[r3:RATED]->(recMovie:Movie)
WHERE r3.rating >= 4 AND NOT EXISTS { (u)-[:RATED]->(recMovie) }
WITH recMovie, count(DISTINCT peer) AS RecommendedByUsers, avg(r3.rating) AS AvgPeerRating
RETURN recMovie.title AS RecommendedMovie, recMovie.year AS Year, RecommendedByUsers, round(AvgPeerRating, 2) AS AveragePeerRating
ORDER BY RecommendedByUsers DESC, AveragePeerRating DESC
LIMIT 10;

// Крок 5 (Варіант Б): Оптимізована фільтрація (Швидкісний)
// Оптимізація за рахунок обмеження вибірки топ-улюблених фільмів та фільтрації однодумців
MATCH (u:User {userId: 1})-[r1:RATED]->(m1:Movie)
WHERE r1.rating >= 4
WITH u, m1 
ORDER BY r1.rating DESC 
LIMIT 15  // Беремо лише 15 найкращих фільмів користувача
MATCH (m1)<-[r2:RATED]-(peer:User)
WHERE r2.rating >= 4 AND u <> peer
WITH u, peer, count(m1) AS intersectionSize
WHERE intersectionSize >= 3 // Тільки ті люди, у кого мінімум 3 спільні фільми з юзером
MATCH (peer)-[r3:RATED]->(recMovie:Movie)
WHERE r3.rating = 5 AND NOT EXISTS { (u)-[:RATED]->(recMovie) } // Тільки фільми з оцінкою 5
WITH recMovie, count(DISTINCT peer) AS RecommendedByUsers, avg(r3.rating) AS AvgPeerRating
RETURN recMovie.title AS RecommendedMovie, recMovie.year AS Year, RecommendedByUsers, round(AvgPeerRating, 2) AS AveragePeerRating
ORDER BY RecommendedByUsers DESC, AveragePeerRating DESC
LIMIT 10;

// Крок 5 (Варіант В): Фільтрація з функцією затухання часу (Time Decay)
// Враховує свіжість оцінок: старі оцінки однодумців втрачають вагу, піднімаючи в топ актуальні тренди
MATCH (u:User {userId: 1})-[r1:RATED]->(m1:Movie)
WHERE r1.rating >= 4
WITH u, m1 
ORDER BY r1.rating DESC 
LIMIT 15
MATCH (m1)<-[r2:RATED]-(peer:User)
WHERE r2.rating >= 4 AND u <> peer
WITH u, peer, count(m1) AS intersectionSize
WHERE intersectionSize >= 3
MATCH (peer)-[r3:RATED]->(recMovie:Movie)
WHERE r3.rating >= 4 AND NOT EXISTS { (u)-[:RATED]->(recMovie) }
// Математичне затухання: переводимо timestamp у дні та рахуємо дельту відносно умовної поточної дати (2026 рік)
// Константа '2026' виступає як жорстко зафіксована точка відліку. 
// Вона гарантує, що дельта часу (currentDays - ratingDays) завжди буде позитивною для старих оцінок з датасету.
// Формула ваги: 1.0 / (1.0 + k * delta), де k = 0.0005 (швидкість затухання).
// Чим старіша оцінка (більша дельта), тим більшим стає знаменник, 
// а отже, підсумкова вага (timeWeight) наближається до нуля. 
// Свіжі оцінки мають малу дельту і отримують вагу, максимально наближену до 1.0.
WITH recMovie, r3,
     (2026 - 1970) * 365 AS currentDays,
     r3.timestamp / 86400 AS ratingDays
WITH recMovie, 
     1.0 / (1.0 + 0.0005 * (currentDays - ratingDays)) AS timeWeight, r3
// Формуємо фінальну силу рекомендації на основі накопиченої ваги свіжих оцінок
WITH recMovie, sum(timeWeight) AS RecommendationStrength, avg(r3.rating) AS AvgPeerRating
RETURN recMovie.title AS RecommendedMovie, recMovie.year AS Year, round(RecommendationStrength, 2) AS RecommendationStrength, round(AvgPeerRating, 2) AS AvgPeerRating
ORDER BY RecommendationStrength DESC
LIMIT 10;

// Крок 6: Найкоротший ланцюжок зв’язку між двома користувачами через фільми
MATCH p = shortestPath((u1:User {userId: 1})-[:RATED*..6]-(u2:User {userId: 10}))
RETURN p;

// Крок 6 (Додатковий експеримент А): Пошук користувачів на максимальній графовій дистанції (знайшлися лише на 4 хопи, на 5 та 6 немає результатів)
MATCH (u1:User {userId: 1})
MATCH p = shortestPath((u1)-[:RATED*..6]-(u2:User))
WHERE u1 <> u2
WITH u2, p
WHERE length(p) = 4
RETURN u2.userId AS RemoteUserID, u2.gender AS Gender, u2.age AS Age, length(p) AS Distance
LIMIT 10;

// Крок 6 (Додатковий запит: Візуалізація шляху): Найкоротший шлях від userId:1 до найвіддаленішого userId:46
MATCH p = shortestPath((u1:User {userId: 1})-[:RATED*..6]-(u2:User {userId: 46}))
RETURN p;