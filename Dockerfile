FROM ubuntu
FROM node:14.15.3-alpine3.10

COPY . .

WORKDIR /usr/src/app

EXPOSE 8008

CMD ["npm", "start"]