# frozen_string_literal: true

class SessionsController < ApplicationController
  def new
    redirect_to root_path if logged_in?
    @demo_users_missing = User.none?
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome, #{user.name}!"
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Logged out."
  end
end
