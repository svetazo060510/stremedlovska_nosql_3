import csv

print("Почалася конвертація файлів MovieLens 1M...")

# 1. movies.dat: MovieID::Title::Genres
print("Конвертація movies.dat -> movies.csv...")
with open('movies.dat', 'r', encoding='latin-1') as f_in, \
     open('import/movies.csv', 'w', newline='', encoding='utf-8') as f_out:
    writer = csv.writer(f_out)
    writer.writerow(['movieId', 'title', 'genres'])
    for line in f_in:
        parts = line.strip().split('::')
        writer.writerow(parts)

# 2. ratings.dat: UserID::MovieID::Rating::Timestamp
print("Конвертація ratings.dat -> ratings.csv...")
with open('ratings.dat', 'r', encoding='latin-1') as f_in, \
     open('import/ratings.csv', 'w', newline='', encoding='utf-8') as f_out:
    writer = csv.writer(f_out)
    writer.writerow(['userId', 'movieId', 'rating', 'timestamp'])
    for line in f_in:
        parts = line.strip().split('::')
        writer.writerow(parts)

# 3. users.dat: UserID::Gender::Age::Occupation::Zip
print("Конвертація users.dat -> users.csv...")
with open('users.dat', 'r', encoding='latin-1') as f_in, \
     open('import/users.csv', 'w', newline='', encoding='utf-8') as f_out:
    writer = csv.writer(f_out)
    writer.writerow(['userId', 'gender', 'age', 'occupation'])
    for line in f_in:
        parts = line.strip().split('::')
        writer.writerow(parts[:4])  # zip не потрібен

print("Конвертація успішно завершена! Файли у папці import/")