# LAMP
Auto Installer LAMP on Ubuntu

```
wget --no-cache -O - https://raw.githubusercontent.com/soheilas/LAMP/master/installer.sh | bash")
```
## Next Steps

### Install phpMyAdmin

Run the below command in terminal to install phpMyAdmin and it's prerequisites:

```bash
sudo apt install phpmyadmin php-mbstring php-gettext
```

And then enable required extensions:

```bash
sudo phpenmod mcrypt
sudo phpenmod mbstring
```
Then restart Apache server:

```bash
sudo systemctl restart apache2
```

Now navigate to the phpMyAdmin:

```bash
xdg-open "http://localhost"
```

---

All done. now you have Apache2, MySQL, PHP installed.
