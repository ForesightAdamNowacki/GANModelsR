# ------------------------------------------------------------------------------
# GENERATIVE ADVERSARIAL MODEL
# ------------------------------------------------------------------------------
# Data:
# https://www.kaggle.com/c/cifar-10/overview
utils::browseURL(url = "https://www.kaggle.com/c/cifar-10/overview")

# ------------------------------------------------------------------------------
# Intro:
base::setwd("D:/GitHub/GANModelsR")

# ------------------------------------------------------------------------------
# Environment:
reticulate::use_condaenv("GPU_ML_2", required = TRUE)
base::library(tensorflow)
base::library(keras)
# keras::install_keras(tensorflow = "gpu")
base::library(tidyverse)
base::library(deepviz)

# ------------------------------------------------------------------------------
# Clear session:
keras::k_clear_session()

# ------------------------------------------------------------------------------
# Hyperparameters:
latent_dim <- 32
height <- 32
width <- 32
channels <- 3

# ------------------------------------------------------------------------------
# Generator:
generator_input <- keras::layer_input(shape = base::c(latent_dim)) # 32
generator_output <- generator_input %>% # 32
  keras::layer_dense(units = 128 * 16 * 16) %>% # 32768
  keras::layer_activation_leaky_relu() %>% # 32768
  keras::layer_reshape(target_shape = base::c(16, 16, 128)) %>% # activation map: 16x16, 128 channels
  keras::layer_conv_2d(filters = 256, kernel_size = 5, strides = 1, activation = "linear", padding = "same") %>% # activation map: 16x16, 256 channels
  keras::layer_activation_leaky_relu() %>% # activation map: 16x16, 256 channels
  keras::layer_conv_2d_transpose(filters = 256, kernel_size = 4, strides = 2, activation = "linear", padding = "same") %>% # activation map: 32x32, 256 channels
  keras::layer_activation_leaky_relu() %>% # activation map: 32x32, 256 channels
  keras::layer_conv_2d(filters = 256, kernel_size = 5, padding = "same") %>% # activation map: 32x32, 256 channels
  keras::layer_activation_leaky_relu() %>% # activation map: 32x32, 256 channels
  keras::layer_conv_2d(filters = 256, kernel_size = 5, padding = "same") %>% # activation map: 32x32, 256 channels
  keras::layer_activation_leaky_relu() %>% # activation map: 32x32, 256 channels
  keras::layer_conv_2d(filters = channels, kernel_size = 7, activation = "tanh", padding = "same") # activation map: 32x32x3
generator <- keras::keras_model(inputs = generator_input, outputs = generator_output) # output: 32x32x3 (the same as CIFAR10)

# ------------------------------------------------------------------------------
# Visualize generator:
generator %>% deepviz::plot_model()
base::summary(generator)

# ------------------------------------------------------------------------------
# Discriminator:
discriminator_input <- keras::layer_input(shape = base::c(height, width, channels)) # 32x32x3
discriminator_output <- discriminator_input %>%  #32x32x3
  keras::layer_conv_2d(filters = 128, kernel_size = 3, strides = 1, activation = "linear") %>% # 30x30x128
  keras::layer_activation_leaky_relu() %>% # 30x30x128
  keras::layer_conv_2d(filters = 128, kernel_size = 4, strides = 2, activation = "linear") %>% # 14x14x128
  keras::layer_activation_leaky_relu() %>% # 14x14x128
  keras::layer_conv_2d(filters = 128, kernel_size = 4, strides = 2, activation = "linear") %>% # 6x6x128
  keras::layer_activation_leaky_relu() %>% # 6x6x128
  keras::layer_conv_2d(filters = 128, kernel_size = 4, strides = 2, activation = "linear") %>% # 2x2x128
  keras::layer_activation_leaky_relu() %>% # 2x2x128
  keras::layer_flatten() %>% # 512
  keras::layer_dropout(rate = 0.4) %>% # 512
  keras::layer_dense(units = 1, activation = "sigmoid") # 1
discriminator <- keras_model(inputs = discriminator_input, outputs = discriminator_output) # 32x32x3 -> binary classification (0-1)

# ------------------------------------------------------------------------------
# Visualize discriminator:
discriminator %>% deepviz::plot_model()
base::summary(discriminator)

# ------------------------------------------------------------------------------
# Model compilation:
discriminator_optimizer <- keras::optimizer_rmsprop(lr = 0.0008, 
                                                    clipvalue = 1.0,
                                                    decay = 1e-8)
discriminator %>% keras::compile(optimizer = discriminator_optimizer,
                                 loss = "binary_crossentropy")

# ------------------------------------------------------------------------------
# Generative Adversarial Model - GAN <- discriminator(generator(x)):
keras::freeze_weights(discriminator) 
gan_input <- keras::layer_input(shape = base::c(latent_dim))
gan_output <- discriminator(generator(gan_input))
gan <- keras::keras_model(inputs = gan_input, outputs = gan_output)
gan_optimizer <- keras::optimizer_rmsprop(lr = 0.0004, 
                                          clipvalue = 1.0, 
                                          decay = 1e-8)
gan %>% keras::compile(optimizer = gan_optimizer, 
                       loss = "binary_crossentropy")

# ------------------------------------------------------------------------------
# DCGAN model training:
cifar10 <- keras::dataset_cifar10()
c(c(x_train, y_train), c(x_test, y_test)) %<-% cifar10
x_train <- x_train[as.integer(y_train) == 6,,,] # only frog class
x_train <- x_train/255
iterations <- 10000
batch_size <- 20
save_images_dir <- "gan_images_folder"
save_models_dir <- "gan_models_folder"
base::dir.create(save_images_dir)
base::dir.create(save_models_dir)

start <- 1
for (step in 1:iterations) {
  
  random_latent_vectors <- base::matrix(stats::rnorm(batch_size * latent_dim), nrow = batch_size, ncol = latent_dim)
  generated_images <- generator %>% stats::predict(random_latent_vectors)

  stop <- start + batch_size - 1 
  real_images <- x_train[start:stop,,,]
  rows <- base::nrow(real_images)
  combined_images <- base::array(0, dim = base::c(rows * 2, base::dim(real_images)[-1]))
  combined_images[1:rows,,,] <- generated_images
  combined_images[(rows+1):(rows*2),,,] <- real_images

  labels <- base::rbind(base::matrix(1, nrow = batch_size, ncol = 1), base::matrix(0, nrow = batch_size, ncol = 1)) # 1 - generated, 0 - real
  labels <- labels + (0.5 * base::array(stats::runif(base::prod(base::dim(labels)), min = 0, max = 1), dim = base::dim(labels))) # random noise added to labels
  
  d_loss <- discriminator %>% keras::train_on_batch(combined_images, labels) # train discriminator

  random_latent_vectors <- base::matrix(stats::rnorm(batch_size * latent_dim, mean = 0, sd = 1), nrow = batch_size, ncol = latent_dim)
  misleading_targets <- base::array(0, dim = base::c(batch_size, 1)) # false labels -> all images as real
  
  a_loss <- gan %>% keras::train_on_batch(random_latent_vectors, misleading_targets) # train gan -> train the generator with frozen discriminator weights
  
  start <- start + batch_size
  if (start > (base::nrow(x_train) - batch_size))
    start <- 1
  
  if (step %% 1000 == 0) { 
    keras::save_model_weights_hdf5(gan, filepath = base::file.path(save_models_dir, base::paste0(step, "_gan.h5")))
    keras::save_model_weights_hdf5(gan, filepath = base::file.path(save_models_dir, base::paste0(step, "_gan.hdf5")))
    base::cat("discriminator loss:", d_loss, "\n")
    base::cat("adversarial loss:", a_loss, "\n")  
    keras::image_array_save(generated_images[1,,,] * 255, path = base::file.path(save_images_dir, base::paste0(step, "_generated_frog.png")))
    keras::image_array_save(real_images[1,,,] * 255, path = base::file.path(save_images_dir, base::paste0(step, "_real_frog.png")))
  }
}





