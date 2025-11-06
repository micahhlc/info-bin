# Below is samples only on bash syntax. 
# below should not be run. 

name="Micah"
age=43
city="Tokyo"

echo "Name: $name, Age: $age, City: $city"
# ⚠️ No spaces around = — name = "Micah" ❌ will break.

x=5
y=3
# sum=$((x + y))
echo "Sum: $sum"
sum=$(expr $x + $y)
echo "Sum: $sum"
result=$(echo "10 / 3" | bc -l)
echo "Result: $result"

fruits=("apple" "banana" "cherry")
echo ${fruits[0]}       # first element
echo ${fruits[@]}       # all elements
echo ${#fruits[@]}      # number of elements

fruits+=("orange")      # add
fruits[1]="grape"       # modify

for fruit in "${fruits[@]}"; do
  echo "I like $fruit"
done

# Associative Arrays (Key–Value Pairs)
# Only in Bash 4+ (macOS now supports it).
declare -A dog
dog[name]="Umi"
dog[age]=1
dog[color]="apricot"

echo "Name: ${dog[name]}, Color: ${dog[color]}"

# Env variables
echo $HOME
echo $PATH
export API_KEY="abcdef123" #create your own key

# read input into a variable
read -p "Enter your name: " username
echo "Hi $username!"

# test variables
if [ -z "$name" ]; then
  echo "Name is empty"
elif [ "$name" = "Micah" ]; then
  echo "Welcome back, Micah!"
else
  echo "Hello, $name"
fi

# Unset / Default Values
unset name             # remove variable
echo ${var:-"default"} # prints 'default' if var is empty


# common string output
echo ${#name}         # length of string
echo ${name:0:3}      # substring (first 3 chars)
echo ${name/M/m}      # replace first 'M' with 'm'


cat basic.sh         # show full file
less basic.sh        # scroll interactively
head -5 basic.sh     # show first 5 lines
tail -n 10 basic.sh  # show last 10 lines


grep "error" log.txt                # find lines containing "error"
grep -i "warning" log.txt           # ignore case
grep -r "function" ~/project/       # search recursively in folder

echo "hello" | tr 'a-z' 'A-Z'       # convert to uppercase
echo "2025-10-21" | tr '-' '/'      # replace '-' with '/'
echo "remove spaces" | tr -d ' '    # delete spaces

echo "name,age,city" | cut -d',' -f2   # output: age
cut -d':' -f1 /etc/passwd              # print usernames


awk '{print $1}' file.txt              # print first column
awk -F, '{print $2}' data.csv          # specify comma delimiter

sed 's/apple/orange/' fruits.txt       # replace first match per line
sed 's/apple/orange/g' fruits.txt      # replace all matches per line
sed -i '' 's/foo/bar/g' file.txt       # replace in-place (macOS)

sort names.txt                         # sort alphabetically
sort -r names.txt                      # reverse order
sort names.txt | uniq                  # remove duplicates

wc -l file.txt   # count lines
wc -w file.txt   # count words
wc -c file.txt   # count characters

expr 5 + 3        # basic math
echo "10 / 3" | bc -l   # division with decimals

chmod +x script.sh        # make script executable
sudo chown micah file.txt # change owner

find ~/Documents -name "*.pdf"
find . -type f -size +100M      # files larger than 100 MB

tar -czf backup.tar.gz folder/
tar -xzf backup.tar.gz
gzip file.txt
gunzip file.txt.gz

for file in *.txt; do
  echo "Processing $file"
done

count=1
while [ $count -le 5 ]; do
  echo "Loop $count"
  ((count++))
done

if [ -f "file.txt" ]; then
  echo "File exists"
else
  echo "File not found"
fi

ls *.txt | xargs rm    # delete all .txt files
cat urls.txt | xargs curl -O  # download all URLs

alias ll='ls -lh'
alias gs='git status'


#!/bin/bash

x=12
y=5

sum=$((x + y))
diff=$((x - y))
prod=$((x * y))
quot=$((x / y))
mod=$((x % y))

echo "x = $x, y = $y"
echo "Addition:      $x + $y = $sum"
echo "Subtraction:   $x - $y = $diff"
echo "Multiplication: $x * $y = $prod"
echo "Division:      $x / $y = $quot"
echo "Modulus:       $x % $y = $mod"

# output 
x = 12, y = 5
Addition:      12 + 5 = 17
Subtraction:   12 - 5 = 7
Multiplication: 12 * 5 = 60
Division:      12 / 5 = 2
Modulus:       12 % 5 = 2

# for folating point.
x=12
y=5
echo "scale=2; $x / $y" | bc