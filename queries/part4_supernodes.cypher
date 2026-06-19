// ==========================================
// ВИЯВЛЕННЯ СУПЕРВУЗЛІВ
// ==========================================

// Запит 1: Пошук супервузлів серед Фільмів (Топ-10 найпопулярніших хабів)
MATCH (m:Movie)<-[r:RATED]-()
WITH m, count(r) AS Degree
ORDER BY Degree DESC
LIMIT 10
RETURN m.title AS MovieTitle, m.year AS ReleaseYear, Degree AS TotalRatings;

// Запит 2: Пошук супервузлів серед Користувачів (Топ-10 аномально активних акаунтів)
MATCH (u:User)-[r:RATED]->()
WITH u, count(r) AS Degree
ORDER BY Degree DESC
LIMIT 10
RETURN u.userId AS UserID, u.gender AS Gender, u.age AS Age, Degree AS TotalRatingsGiven;